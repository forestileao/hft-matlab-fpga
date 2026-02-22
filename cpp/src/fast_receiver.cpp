#include "SimpleMD.h"
#include "fpga_shared_stream.h"
#include <mfast/coder/fast_decoder.h>
#include <iostream>
#include <vector>
#include <boost/exception/diagnostic_information.hpp>
#include <cerrno>
#include <cmath>
#include <cstdlib>
#include <cstring>
#include <sys/socket.h>
#include <arpa/inet.h>
#include <unistd.h>

static const char* SERVER_IP   = "127.0.0.1";
static const int   SERVER_PORT = 9001;

static bool parse_u64(const char* text, uint64_t* out)
{
    if (text == nullptr || out == nullptr) {
        return false;
    }
    errno = 0;
    char* end = nullptr;
    unsigned long long value = std::strtoull(text, &end, 0);
    if (errno != 0 || end == text || *end != '\0') {
        return false;
    }
    *out = static_cast<uint64_t>(value);
    return true;
}

static uint32_t pack_symbol_side(const char* symbol, const char* side)
{
    uint32_t packed = 0;
    for (int i = 0; i < 3; ++i) {
        const uint8_t c = symbol != nullptr && symbol[i] != '\0'
                            ? static_cast<uint8_t>(symbol[i])
                            : static_cast<uint8_t>(' ');
        packed |= (static_cast<uint32_t>(c) << (8 * i));
    }

    uint8_t side_code = 0;
    if (side != nullptr) {
        if (side[0] == 'b' || side[0] == 'B') {
            side_code = 1;
        } else if (side[0] == 's' || side[0] == 'S') {
            side_code = 2;
        }
    }
    packed |= (static_cast<uint32_t>(side_code) << 24);
    return packed;
}

static uint32_t price_to_fixed_1e4(const mfast::decimal_cref& price)
{
    const double value = static_cast<double>(price.mantissa()) *
                         std::pow(10.0, static_cast<double>(price.exponent()));
    long long scaled = std::llround(value * 10000.0);
    if (scaled < 0) {
        scaled = 0;
    } else if (scaled > 0xFFFFFFFFll) {
        scaled = 0xFFFFFFFFll;
    }
    return static_cast<uint32_t>(scaled);
}

static bool init_fpga_bridge(FpgaSharedStream* bridge)
{
    const char* base_env = std::getenv("HFT_FPGA_MMIO_BASE");
    if (base_env == nullptr) {
        std::cout << "FPGA MMIO bridge disabled (set HFT_FPGA_MMIO_BASE to enable)\n";
        return false;
    }

    uint64_t base = 0;
    if (!parse_u64(base_env, &base)) {
        std::cerr << "Invalid HFT_FPGA_MMIO_BASE value: " << base_env << "\n";
        return false;
    }

    std::size_t span = FpgaSharedStream::kDefaultSpan;
    const char* span_env = std::getenv("HFT_FPGA_MMIO_SPAN");
    if (span_env != nullptr) {
        uint64_t parsed_span = 0;
        if (!parse_u64(span_env, &parsed_span) || parsed_span == 0) {
            std::cerr << "Invalid HFT_FPGA_MMIO_SPAN value: " << span_env << "\n";
            return false;
        }
        span = static_cast<std::size_t>(parsed_span);
    }

    const char* dev_env = std::getenv("HFT_FPGA_MMIO_DEV");
    const std::string dev_path = dev_env == nullptr ? "/dev/mem" : dev_env;

    if (!bridge->Open(base, span, dev_path)) {
        std::cerr << "Failed to open FPGA MMIO bridge at base=0x" << std::hex << base
                  << " span=0x" << span << " dev=" << dev_path << std::dec << "\n";
        return false;
    }

    std::cout << "FPGA MMIO bridge enabled: base=0x" << std::hex << base
              << " span=0x" << span << " magic=0x" << bridge->Magic()
              << " version=" << std::dec << bridge->Version()
              << " tx_depth=" << bridge->TxDepth()
              << " rx_depth=" << bridge->RxDepth() << "\n";
    return true;
}

int main()
{
    int sock = socket(AF_INET, SOCK_STREAM, 0);
    if (sock < 0) { perror("socket"); return 1; }

    sockaddr_in serv{};
    serv.sin_family = AF_INET;
    serv.sin_port   = htons(SERVER_PORT);
    inet_pton(AF_INET, SERVER_IP, &serv.sin_addr);

    if (connect(sock, (sockaddr*)&serv, sizeof(serv)) < 0) {
        perror("connect");
        return 1;
    }

    std::cout << "Connected to " << SERVER_IP << ":" << SERVER_PORT << "\n";

    mfast::fast_decoder decoder;
    const mfast::templates_description* descs[] = { SimpleMD::description() };
    decoder.include(descs);

    FpgaSharedStream bridge;
    const bool bridge_enabled = init_fpga_bridge(&bridge);

    auto read_exact = [&](void* dst, size_t len) -> bool {
        char* p = static_cast<char*>(dst);
        size_t remaining = len;
        while (remaining > 0) {
            ssize_t n = read(sock, p, remaining);
            if (n <= 0) return false;
            p += n;
            remaining -= n;
        }
        return true;
    };

    std::vector<char> buf(8192);

    while (true) {
        uint32_t frame_len_net;
        if (!read_exact(&frame_len_net, sizeof(frame_len_net))) break;
        uint32_t msg_len = ntohl(frame_len_net);

        if (msg_len > buf.size()) buf.resize(msg_len);
        if (!read_exact(buf.data(), msg_len)) break;

        const char* p   = buf.data();
        const char* end = buf.data() + msg_len;

        try {
            mfast::message_cref msg = decoder.decode(p, end, true);
            SimpleMD::SimpleMD_cref typed(msg);

            for (auto entry : typed.get_MDEntries()) {
                std::cout
                    << "seq="    << entry.get_SeqNo().value()
                    << " sym="   << entry.get_Symbol().c_str()
                    << " side="  << entry.get_Side().c_str()
                    << " price=" << entry.get_Price().value()
                    << " qty="   << entry.get_Qty().value()
                    << "\n";

                if (bridge_enabled) {
                    FpgaSharedStream::Frame frame{};
                    frame.word0 = entry.get_SeqNo().value();
                    frame.word1 = pack_symbol_side(entry.get_Symbol().c_str(),
                                                   entry.get_Side().c_str());
                    frame.word2 = price_to_fixed_1e4(entry.get_Price());
                    frame.word3 = entry.get_Qty().value();

                    if (!bridge.Send(frame)) {
                        std::cerr << "FPGA TX queue full, dropping seq="
                                  << frame.word0 << "\n";
                    }
                }
            }

            if (bridge_enabled) {
                FpgaSharedStream::Frame rx{};
                while (bridge.Receive(&rx)) {
                    std::cout << "[FPGA->ARM] w0=" << rx.word0
                              << " w1=0x" << std::hex << rx.word1
                              << " w2=" << std::dec << rx.word2
                              << " w3=" << rx.word3 << "\n";
                }
            }
        } catch (const boost::exception& e) {
            std::cerr << "FAST decode error (msg_len=" << msg_len << "):\n"
                      << boost::diagnostic_information(e) << "\n";
            break;
        } catch (const std::exception& e) {
            std::cerr << "Decode error: " << e.what() << "\n";
            break;
        }
    }

    close(sock);
    return 0;
}
