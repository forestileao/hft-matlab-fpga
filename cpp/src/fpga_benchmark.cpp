#include "fpga_shared_stream.h"

#include <algorithm>
#include <cerrno>
#include <cmath>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <fcntl.h>
#include <iomanip>
#include <iostream>
#include <string>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>
#include <vector>

namespace {

const uint32_t kEventUpsertLevel = 1;
const uint32_t kEventDeleteLevel = 2;
const uint32_t kEventResetBook = 3;
const uint32_t kSideBuy = 1;
const uint32_t kSideSell = 2;
const uint32_t kActionNoop = 0;
const uint32_t kActionBuy = 1;
const uint32_t kActionSell = 2;
const uint32_t kNumSymbols = 8;
const uint32_t kBookDepth = 8;
const uint32_t kImbalanceThreshold = 500;
const uint32_t kMaxSpread1e4 = 25000;
const double kLatencyJitterLimitNs = 1000.0;
const double kThroughputLimitMsgS = 100000.0;
const double kSpeedupLimit = 5.0;

struct Options {
  std::string mode;
  uint64_t messages;
  uint64_t warmup;
  bool enable_bridges;
  bool enable_bridges_only;
};

struct BenchmarkResult {
  bool ran;
  uint64_t messages;
  uint64_t duration_ns;
  double throughput_msg_s;
  uint64_t checksum;
  uint64_t tx_full_spins;
  uint64_t rx_empty_spins;
  FpgaSharedStream::PerfCounters perf;
};

struct SoftwareResult {
  bool ran;
  uint64_t messages;
  uint64_t duration_ns;
  double avg_ns;
  uint64_t checksum;
};

struct Level {
  uint32_t price;
  uint32_t qty;
};

struct Book {
  Level bids[kNumSymbols][kBookDepth];
  Level asks[kNumSymbols][kBookDepth];
};

uint64_t now_ns() {
  timespec ts{};
#ifdef CLOCK_MONOTONIC_RAW
  const clockid_t clock_id = CLOCK_MONOTONIC_RAW;
#else
  const clockid_t clock_id = CLOCK_MONOTONIC;
#endif
  clock_gettime(clock_id, &ts);
  return static_cast<uint64_t>(ts.tv_sec) * 1000000000ull +
         static_cast<uint64_t>(ts.tv_nsec);
}

bool parse_u64(const char* text, uint64_t* out) {
  if (text == nullptr || out == nullptr) {
    return false;
  }
  errno = 0;
  char* end = nullptr;
  const unsigned long long value = std::strtoull(text, &end, 0);
  if (errno != 0 || end == text || *end != '\0') {
    return false;
  }
  *out = static_cast<uint64_t>(value);
  return true;
}

void usage(const char* argv0) {
  std::cerr
      << "Usage: " << argv0
      << " [--mode fpga-mmio|sw-core|full] [--messages N] [--warmup N]\n";
  std::cerr << "       " << argv0 << " --enable-bridges-only\n";
}

bool parse_args(int argc, char** argv, Options* options) {
  if (options == nullptr) {
    return false;
  }
  options->mode = "full";
  options->messages = 1000000;
  options->warmup = 10000;
  options->enable_bridges = false;
  options->enable_bridges_only = false;

  for (int i = 1; i < argc; ++i) {
    const std::string arg(argv[i]);
    if (arg == "--help" || arg == "-h") {
      usage(argv[0]);
      std::exit(0);
    }
    if ((arg == "--mode" || arg == "--messages" || arg == "--warmup") && i + 1 >= argc) {
      usage(argv[0]);
      return false;
    }
    if (arg == "--mode") {
      options->mode = argv[++i];
    } else if (arg == "--messages") {
      if (!parse_u64(argv[++i], &options->messages) || options->messages == 0) {
        std::cerr << "Invalid --messages value\n";
        return false;
      }
    } else if (arg == "--warmup") {
      if (!parse_u64(argv[++i], &options->warmup)) {
        std::cerr << "Invalid --warmup value\n";
        return false;
      }
    } else if (arg == "--enable-bridges") {
      options->enable_bridges = true;
    } else if (arg == "--enable-bridges-only") {
      options->enable_bridges = true;
      options->enable_bridges_only = true;
    } else {
      usage(argv[0]);
      return false;
    }
  }

  if (options->mode != "fpga-mmio" && options->mode != "sw-core" &&
      options->mode != "full") {
    std::cerr << "Invalid --mode value\n";
    return false;
  }
  return true;
}

bool enable_hps_fpga_bridges() {
  const uint64_t kBridgeResetReg = 0xFFD0501Cull;
  const uint32_t kBridgeResetMask = 0x7u;  // h2f, lightweight h2f, f2h

  const char* dev_env = std::getenv("HFT_FPGA_MMIO_DEV");
  const std::string dev_path = dev_env == nullptr ? "/dev/mem" : dev_env;

  const long page_size = sysconf(_SC_PAGESIZE);
  if (page_size <= 0) {
    std::cerr << "Invalid page size while enabling HPS bridges\n";
    return false;
  }

  const uint64_t page_mask = static_cast<uint64_t>(page_size - 1);
  const uint64_t aligned_base = kBridgeResetReg & ~page_mask;
  const std::size_t page_off = static_cast<std::size_t>(kBridgeResetReg - aligned_base);

  const int fd = open(dev_path.c_str(), O_RDWR | O_SYNC);
  if (fd < 0) {
    std::cerr << "Failed to open " << dev_path << " while enabling HPS bridges: "
              << std::strerror(errno) << "\n";
    return false;
  }

  void* map = mmap(nullptr, static_cast<std::size_t>(page_size),
                   PROT_READ | PROT_WRITE, MAP_SHARED, fd,
                   static_cast<off_t>(aligned_base));
  if (map == MAP_FAILED) {
    std::cerr << "Failed to mmap HPS reset manager: " << std::strerror(errno) << "\n";
    close(fd);
    return false;
  }

  volatile uint32_t* reg =
      reinterpret_cast<volatile uint32_t*>(reinterpret_cast<uint8_t*>(map) + page_off);
  const uint32_t before = *reg;
  const uint32_t after = before & ~kBridgeResetMask;
  *reg = after;
  __sync_synchronize();

  munmap(map, static_cast<std::size_t>(page_size));
  close(fd);

  std::cerr << "HPS FPGA bridge reset register: before=0x" << std::hex << before
            << " after=0x" << after << std::dec << "\n";
  return true;
}

FpgaSharedStream::Frame make_event(uint64_t idx) {
  static const uint32_t base_prices_1e4[5] = {
      1850000u, 4150000u, 8750000u, 1700000u, 1750000u,
  };

  const uint32_t symbol = static_cast<uint32_t>(idx % 5);
  const uint32_t side = (idx & 1u) == 0 ? kSideBuy : kSideSell;
  const uint32_t ticks_1e4 = static_cast<uint32_t>(((idx * 17u) % 80u) + 1u) * 100u;
  const uint32_t base = base_prices_1e4[symbol];
  const uint32_t price = side == kSideBuy ? base - ticks_1e4 : base + ticks_1e4;
  const uint32_t qty = 100u + static_cast<uint32_t>((idx * 37u) % 4901u);

  FpgaSharedStream::Frame frame{};
  frame.word0 = static_cast<uint32_t>(idx + 1u);
  frame.word1 = symbol;
  frame.word2 = price;
  frame.word3 = qty;
  frame.word4 = kEventUpsertLevel;
  frame.word5 = side;
  frame.word6 = 0;
  frame.word7 = 0;
  return frame;
}

std::vector<FpgaSharedStream::Frame> make_events(uint64_t total) {
  std::vector<FpgaSharedStream::Frame> events;
  events.reserve(static_cast<std::size_t>(total));
  for (uint64_t i = 0; i < total; ++i) {
    events.push_back(make_event(i));
  }
  return events;
}

void clear_side(Level side[kBookDepth]) {
  for (uint32_t i = 0; i < kBookDepth; ++i) {
    side[i].price = 0;
    side[i].qty = 0;
  }
}

void delete_at(Level side[kBookDepth], uint32_t idx) {
  for (uint32_t i = idx; i + 1 < kBookDepth; ++i) {
    side[i] = side[i + 1];
  }
  side[kBookDepth - 1].price = 0;
  side[kBookDepth - 1].qty = 0;
}

void apply_level_update(Level side[kBookDepth], uint32_t price, uint32_t qty,
                        bool is_delete, bool desc_sort) {
  int match_idx = -1;
  int insert_idx = -1;
  for (uint32_t i = 0; i < kBookDepth; ++i) {
    if (side[i].qty != 0 && side[i].price == price) {
      match_idx = static_cast<int>(i);
    }
  }

  if (match_idx >= 0) {
    if (is_delete || qty == 0) {
      delete_at(side, static_cast<uint32_t>(match_idx));
    } else {
      side[match_idx].qty = qty;
    }
    return;
  }

  if (is_delete || qty == 0) {
    return;
  }

  for (uint32_t i = 0; i < kBookDepth; ++i) {
    if (side[i].qty == 0) {
      insert_idx = static_cast<int>(i);
      break;
    }
    if ((desc_sort && price > side[i].price) ||
        (!desc_sort && price < side[i].price)) {
      insert_idx = static_cast<int>(i);
      break;
    }
  }

  if (insert_idx < 0) {
    return;
  }

  for (int i = static_cast<int>(kBookDepth) - 1; i > insert_idx; --i) {
    side[i] = side[i - 1];
  }
  side[insert_idx].price = price;
  side[insert_idx].qty = qty;
}

uint32_t decide_action(uint32_t best_bid_px, uint32_t best_bid_qty,
                       uint32_t best_ask_px, uint32_t best_ask_qty,
                       uint32_t spread_1e4, int32_t imbalance) {
  if (best_bid_qty == 0 || best_ask_qty == 0 || best_ask_px <= best_bid_px) {
    return kActionNoop;
  }
  if (spread_1e4 <= kMaxSpread1e4 &&
      imbalance >= static_cast<int32_t>(kImbalanceThreshold)) {
    return kActionBuy;
  }
  if (spread_1e4 <= kMaxSpread1e4 &&
      imbalance <= -static_cast<int32_t>(kImbalanceThreshold)) {
    return kActionSell;
  }
  return kActionNoop;
}

FpgaSharedStream::Frame process_sw(Book* book, const FpgaSharedStream::Frame& event) {
  const uint32_t symbol = event.word1;
  const uint32_t price = event.word2;
  const uint32_t qty = event.word3;
  const uint32_t event_type = event.word4;
  const uint32_t side = event.word5;

  uint32_t best_bid_px = 0;
  uint32_t best_bid_qty = 0;
  uint32_t best_ask_px = 0;
  uint32_t best_ask_qty = 0;
  uint32_t spread = 0;
  int32_t imbalance = 0;

  if (book != nullptr && symbol < kNumSymbols) {
    if (event_type == kEventResetBook) {
      clear_side(book->bids[symbol]);
      clear_side(book->asks[symbol]);
    } else if (side == kSideBuy) {
      if (event_type == kEventDeleteLevel || book->asks[symbol][0].qty == 0 ||
          price < book->asks[symbol][0].price) {
        apply_level_update(book->bids[symbol], price, qty,
                           event_type == kEventDeleteLevel, true);
      }
    } else if (side == kSideSell) {
      if (event_type == kEventDeleteLevel || book->bids[symbol][0].qty == 0 ||
          price > book->bids[symbol][0].price) {
        apply_level_update(book->asks[symbol], price, qty,
                           event_type == kEventDeleteLevel, false);
      }
    }

    best_bid_px = book->bids[symbol][0].price;
    best_bid_qty = book->bids[symbol][0].qty;
    best_ask_px = book->asks[symbol][0].price;
    best_ask_qty = book->asks[symbol][0].qty;
    if (best_bid_qty != 0 && best_ask_qty != 0 && best_ask_px > best_bid_px) {
      spread = best_ask_px - best_bid_px;
    }
    imbalance = static_cast<int32_t>(best_bid_qty) - static_cast<int32_t>(best_ask_qty);
  }

  FpgaSharedStream::Frame response{};
  response.word0 = event.word0;
  response.word1 = decide_action(best_bid_px, best_bid_qty, best_ask_px, best_ask_qty,
                                 spread, imbalance);
  response.word2 = best_bid_px;
  response.word3 = best_bid_qty;
  response.word4 = best_ask_px;
  response.word5 = best_ask_qty;
  response.word6 = spread;
  response.word7 = static_cast<uint32_t>(imbalance);
  return response;
}

uint64_t checksum_frame(const FpgaSharedStream::Frame& frame) {
  uint64_t value = frame.word0;
  value = (value * 1315423911ull) ^ frame.word1;
  value = (value * 1315423911ull) ^ frame.word2;
  value = (value * 1315423911ull) ^ frame.word3;
  value = (value * 1315423911ull) ^ frame.word4;
  value = (value * 1315423911ull) ^ frame.word5;
  value = (value * 1315423911ull) ^ frame.word6;
  value = (value * 1315423911ull) ^ frame.word7;
  return value;
}

SoftwareResult run_sw_core(const std::vector<FpgaSharedStream::Frame>& events,
                           uint64_t warmup, uint64_t messages) {
  Book book{};
  for (uint64_t i = 0; i < warmup; ++i) {
    process_sw(&book, events[static_cast<std::size_t>(i)]);
  }

  uint64_t checksum = 0;
  const uint64_t start = now_ns();
  for (uint64_t i = 0; i < messages; ++i) {
    const FpgaSharedStream::Frame response =
        process_sw(&book, events[static_cast<std::size_t>(warmup + i)]);
    checksum ^= checksum_frame(response);
  }
  const uint64_t duration = now_ns() - start;

  SoftwareResult result{};
  result.ran = true;
  result.messages = messages;
  result.duration_ns = duration;
  result.avg_ns = messages == 0 ? 0.0 : static_cast<double>(duration) / messages;
  result.checksum = checksum;
  return result;
}

bool open_bridge(FpgaSharedStream* bridge) {
  const char* base_env = std::getenv("HFT_FPGA_MMIO_BASE");
  if (base_env == nullptr) {
    std::cerr << "HFT_FPGA_MMIO_BASE is required for FPGA benchmark modes\n";
    return false;
  }

  uint64_t base = 0;
  if (!parse_u64(base_env, &base)) {
    std::cerr << "Invalid HFT_FPGA_MMIO_BASE value\n";
    return false;
  }

  uint64_t span_value = FpgaSharedStream::kDefaultSpan;
  const char* span_env = std::getenv("HFT_FPGA_MMIO_SPAN");
  if (span_env != nullptr && !parse_u64(span_env, &span_value)) {
    std::cerr << "Invalid HFT_FPGA_MMIO_SPAN value\n";
    return false;
  }

  const char* dev_env = std::getenv("HFT_FPGA_MMIO_DEV");
  const std::string dev_path = dev_env == nullptr ? "/dev/mem" : dev_env;

  if (!bridge->Open(base, static_cast<std::size_t>(span_value), dev_path)) {
    std::cerr << "Failed to open FPGA MMIO bridge: " << bridge->LastError() << "\n";
    return false;
  }
  return true;
}

bool run_fpga_messages(FpgaSharedStream* bridge,
                       const std::vector<FpgaSharedStream::Frame>& events,
                       uint64_t start_index, uint64_t messages,
                       BenchmarkResult* result) {
  uint64_t sent = 0;
  uint64_t received = 0;
  uint64_t checksum = 0;
  uint64_t tx_full_spins = 0;
  uint64_t rx_empty_spins = 0;
  const uint64_t start = now_ns();

  while (received < messages) {
    bool made_progress = false;

    while (sent < messages && bridge->Send(events[static_cast<std::size_t>(start_index + sent)])) {
      ++sent;
      made_progress = true;
    }

    if (sent < messages) {
      ++tx_full_spins;
    }

    FpgaSharedStream::Frame response{};
    bool received_any = false;
    while (bridge->Receive(&response)) {
      checksum ^= checksum_frame(response);
      ++received;
      received_any = true;
      made_progress = true;
      if (received == messages) {
        break;
      }
    }

    if (!received_any && sent > received) {
      ++rx_empty_spins;
    }

    if (!made_progress) {
      __sync_synchronize();
    }
  }

  const uint64_t duration = now_ns() - start;
  FpgaSharedStream::PerfCounters perf{};
  bridge->ReadPerfCounters(&perf);

  if (result != nullptr) {
    result->ran = true;
    result->messages = messages;
    result->duration_ns = duration;
    result->throughput_msg_s =
        duration == 0 ? 0.0 : (static_cast<double>(messages) * 1000000000.0) /
                                  static_cast<double>(duration);
    result->checksum = checksum;
    result->tx_full_spins = tx_full_spins;
    result->rx_empty_spins = rx_empty_spins;
    result->perf = perf;
  }
  return true;
}

bool run_fpga_benchmark(const std::vector<FpgaSharedStream::Frame>& events,
                        uint64_t warmup, uint64_t messages,
                        BenchmarkResult* result) {
  FpgaSharedStream bridge;
  if (!open_bridge(&bridge)) {
    return false;
  }
  if (!bridge.ResetQueues() || !bridge.ResetPerfCounters()) {
    std::cerr << "Failed to reset FPGA queues/performance counters\n";
    return false;
  }

  BenchmarkResult ignored{};
  if (warmup > 0 && !run_fpga_messages(&bridge, events, 0, warmup, &ignored)) {
    return false;
  }

  if (!bridge.ResetQueues() || !bridge.ResetPerfCounters()) {
    std::cerr << "Failed to reset FPGA before measured run\n";
    return false;
  }

  return run_fpga_messages(&bridge, events, warmup, messages, result);
}

double cycles_to_ns(double cycles, uint32_t clock_hz) {
  if (clock_hz == 0) {
    return 0.0;
  }
  return cycles * 1000000000.0 / static_cast<double>(clock_hz);
}

void print_json(const Options& options, const BenchmarkResult& fpga,
                const SoftwareResult& sw) {
  const double avg_cycles =
      fpga.perf.count == 0
          ? 0.0
          : static_cast<double>(fpga.perf.sum_latency_cycles) /
                static_cast<double>(fpga.perf.count);
  const double min_ns = cycles_to_ns(fpga.perf.min_latency_cycles, fpga.perf.clock_hz);
  const double max_ns = cycles_to_ns(fpga.perf.max_latency_cycles, fpga.perf.clock_hz);
  const double avg_ns = cycles_to_ns(avg_cycles, fpga.perf.clock_hz);
  const double jitter_ns = max_ns >= min_ns ? max_ns - min_ns : 0.0;
  const double speedup_core = (sw.ran && avg_ns > 0.0) ? sw.avg_ns / avg_ns : 0.0;

  std::cout << std::fixed << std::setprecision(3);
  std::cout << "{\n";
  std::cout << "  \"mode\": \"" << options.mode << "\",\n";
  std::cout << "  \"messages\": " << options.messages << ",\n";
  std::cout << "  \"warmup\": " << options.warmup << ",\n";
  std::cout << "  \"duration_ns\": " << (fpga.ran ? fpga.duration_ns : sw.duration_ns) << ",\n";
  std::cout << "  \"throughput_msg_s\": " << (fpga.ran ? fpga.throughput_msg_s : 0.0) << ",\n";
  std::cout << "  \"fpga_latency_min_cycles\": " << fpga.perf.min_latency_cycles << ",\n";
  std::cout << "  \"fpga_latency_max_cycles\": " << fpga.perf.max_latency_cycles << ",\n";
  std::cout << "  \"fpga_latency_avg_cycles\": " << avg_cycles << ",\n";
  std::cout << "  \"fpga_latency_min_ns\": " << min_ns << ",\n";
  std::cout << "  \"fpga_latency_max_ns\": " << max_ns << ",\n";
  std::cout << "  \"fpga_latency_avg_ns\": " << avg_ns << ",\n";
  std::cout << "  \"fpga_latency_jitter_ns\": " << jitter_ns << ",\n";
  std::cout << "  \"sw_core_avg_ns\": " << (sw.ran ? sw.avg_ns : 0.0) << ",\n";
  std::cout << "  \"speedup_core\": " << speedup_core << ",\n";
  std::cout << "  \"tx_full_spins\": " << fpga.tx_full_spins << ",\n";
  std::cout << "  \"rx_empty_spins\": " << fpga.rx_empty_spins << ",\n";
  std::cout << "  \"cmd_stall_cycles\": " << fpga.perf.cmd_stall_cycles << ",\n";
  std::cout << "  \"rsp_stall_cycles\": " << fpga.perf.rsp_stall_cycles << ",\n";
  std::cout << "  \"fpga_measured_count\": " << fpga.perf.count << ",\n";
  std::cout << "  \"fpga_checksum\": " << fpga.checksum << ",\n";
  std::cout << "  \"sw_checksum\": " << sw.checksum << ",\n";
  std::cout << "  \"pass_latency_jitter\": "
            << (fpga.ran && jitter_ns < kLatencyJitterLimitNs ? "true" : "false") << ",\n";
  std::cout << "  \"pass_throughput\": "
            << (fpga.ran && fpga.throughput_msg_s >= kThroughputLimitMsgS ? "true" : "false") << ",\n";
  std::cout << "  \"pass_speedup\": "
            << (sw.ran && fpga.ran && speedup_core >= kSpeedupLimit ? "true" : "false") << "\n";
  std::cout << "}\n";
}

}  // namespace

int main(int argc, char** argv) {
  Options options{};
  if (!parse_args(argc, argv, &options)) {
    return 2;
  }

  if (options.enable_bridges && !enable_hps_fpga_bridges()) {
    return 1;
  }
  if (options.enable_bridges_only) {
    return 0;
  }

  const uint64_t total = options.warmup + options.messages;
  const std::vector<FpgaSharedStream::Frame> events = make_events(total);

  BenchmarkResult fpga{};
  SoftwareResult sw{};

  if (options.mode == "sw-core" || options.mode == "full") {
    sw = run_sw_core(events, options.warmup, options.messages);
  }

  if (options.mode == "fpga-mmio" || options.mode == "full") {
    if (!run_fpga_benchmark(events, options.warmup, options.messages, &fpga)) {
      return 1;
    }
  }

  print_json(options, fpga, sw);
  return 0;
}
