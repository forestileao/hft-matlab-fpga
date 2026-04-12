#pragma once

#include <cstddef>
#include <cstdint>
#include <string>

#include <fcntl.h>
#include <sys/mman.h>
#include <unistd.h>

class FpgaSharedStream {
 public:
  struct Frame {
    uint32_t word0;
    uint32_t word1;
    uint32_t word2;
    uint32_t word3;
    uint32_t word4;
    uint32_t word5;
    uint32_t word6;
    uint32_t word7;
  };

  struct Header {
    uint32_t magic;
    uint32_t version;
    uint32_t tx_depth;
    uint32_t rx_depth;
    uint32_t slot_words;
  };

  static const uint32_t kMagic = 0x48465431;  // "HFT1"
  static const std::size_t kDefaultSpan = 0x2000;
  static const uint32_t kFrameWords = 8;

  FpgaSharedStream()
      : fd_(-1),
        map_base_(MAP_FAILED),
        map_len_(0),
        mmio_(nullptr),
        tx_depth_(kDefaultDepth),
        rx_depth_(kDefaultDepth),
        slot_words_(kDefaultSlotWords),
        observed_header_{} {}

  ~FpgaSharedStream() { Close(); }

  bool Open(uint64_t phys_base, std::size_t span, const std::string& dev_path) {
    Close();
    last_error_.clear();

    const long page_size = sysconf(_SC_PAGESIZE);
    if (page_size <= 0 || span == 0) {
      last_error_ = "invalid page size or MMIO span";
      return false;
    }

    const uint64_t page_mask = static_cast<uint64_t>(page_size - 1);
    const uint64_t aligned_base = phys_base & ~page_mask;
    const std::size_t page_off = static_cast<std::size_t>(phys_base - aligned_base);
    const std::size_t map_len = page_off + span;

    fd_ = open(dev_path.c_str(), O_RDWR | O_SYNC);
    if (fd_ < 0) {
      last_error_ = "failed to open MMIO device";
      return false;
    }

    map_base_ = mmap(nullptr, map_len, PROT_READ | PROT_WRITE, MAP_SHARED, fd_,
                     static_cast<off_t>(aligned_base));
    if (map_base_ == MAP_FAILED) {
      close(fd_);
      fd_ = -1;
      last_error_ = "failed to mmap MMIO region";
      return false;
    }

    map_len_ = map_len;
    mmio_ = reinterpret_cast<volatile uint8_t*>(map_base_) + page_off;

    observed_header_.magic = ReadReg(kRegMagic);
    observed_header_.version = ReadReg(kRegVersion);
    observed_header_.tx_depth = ReadReg(kRegTxDepth);
    observed_header_.rx_depth = ReadReg(kRegRxDepth);
    observed_header_.slot_words = ReadReg(kRegSlotWords);

    if (observed_header_.magic != kMagic || observed_header_.version != kVersion) {
      last_error_ =
          "unexpected bridge header; check HFT_FPGA_MMIO_BASE and loaded bitstream";
      Close();
      return false;
    }

    tx_depth_ = observed_header_.tx_depth == 0 ? kDefaultDepth : observed_header_.tx_depth;
    rx_depth_ = observed_header_.rx_depth == 0 ? kDefaultDepth : observed_header_.rx_depth;
    slot_words_ =
        observed_header_.slot_words == 0 ? kDefaultSlotWords : observed_header_.slot_words;

    if (!IsValidGeometry(span)) {
      last_error_ =
          "unexpected bridge geometry; check the software/FPGA frame contract";
      Close();
      return false;
    }

    return true;
  }

  void Close() {
    if (map_base_ != MAP_FAILED) {
      munmap(map_base_, map_len_);
      map_base_ = MAP_FAILED;
    }
    if (fd_ >= 0) {
      close(fd_);
      fd_ = -1;
    }
    mmio_ = nullptr;
    map_len_ = 0;
    tx_depth_ = kDefaultDepth;
    rx_depth_ = kDefaultDepth;
    slot_words_ = kDefaultSlotWords;
  }

  bool IsOpen() const { return mmio_ != nullptr; }
  const std::string& LastError() const { return last_error_; }
  Header ObservedHeader() const { return observed_header_; }

  bool CanSend() const {
    if (!IsOpen()) {
      return false;
    }
    const uint32_t head = ReadReg(kRegTxHead);
    const uint32_t tail = ReadReg(kRegTxTail);
    return Next(head, tx_depth_) != tail;
  }

  bool IsTxFull() const { return !CanSend(); }

  bool Send(const Frame& frame) {
    if (!IsOpen()) {
      return false;
    }
    if (slot_words_ < kFrameWords) {
      return false;
    }

    const uint32_t head = ReadReg(kRegTxHead);
    const uint32_t tail = ReadReg(kRegTxTail);
    const uint32_t next = Next(head, tx_depth_);
    if (next == tail) {
      return false;
    }

    WriteSlot(kTxBase, head, frame);
    WriteReg(kRegTxHead, next);
    return true;
  }

  bool HasRx() const {
    if (!IsOpen()) {
      return false;
    }
    const uint32_t head = ReadReg(kRegRxHead);
    const uint32_t tail = ReadReg(kRegRxTail);
    return head != tail;
  }

  bool Receive(Frame* frame) {
    if (!IsOpen() || frame == nullptr) {
      return false;
    }
    if (slot_words_ < kFrameWords) {
      return false;
    }

    const uint32_t head = ReadReg(kRegRxHead);
    const uint32_t tail = ReadReg(kRegRxTail);
    if (head == tail) {
      return false;
    }

    ReadSlot(RxBase(), tail, frame);
    WriteReg(kRegRxTail, Next(tail, rx_depth_));
    return true;
  }

  uint32_t Magic() const { return IsOpen() ? ReadReg(kRegMagic) : 0; }
  uint32_t Version() const { return IsOpen() ? ReadReg(kRegVersion) : 0; }
  uint32_t TxDepth() const { return tx_depth_; }
  uint32_t RxDepth() const { return rx_depth_; }
  uint32_t SlotWords() const { return slot_words_; }
  uint32_t RxBase() const { return kTxBase + tx_depth_ * slot_words_ * sizeof(uint32_t); }

 private:
  static const uint32_t kVersion = 1;
  static const uint32_t kDefaultDepth = 64;
  static const uint32_t kDefaultSlotWords = 8;  // 8 x 32-bit words = 256 bits
  static const uint32_t kMaxDepth = 1024;
  static const uint32_t kMaxSlotWords = 64;

  static const uint32_t kRegMagic = 0x000;
  static const uint32_t kRegVersion = 0x004;
  static const uint32_t kRegTxHead = 0x010;
  static const uint32_t kRegTxTail = 0x014;
  static const uint32_t kRegRxHead = 0x018;
  static const uint32_t kRegRxTail = 0x01C;
  static const uint32_t kRegTxDepth = 0x020;
  static const uint32_t kRegRxDepth = 0x024;
  static const uint32_t kRegSlotWords = 0x028;

  static const uint32_t kTxBase = 0x100;

  bool IsValidGeometry(std::size_t span) const {
    if (tx_depth_ < 2 || rx_depth_ < 2 || tx_depth_ > kMaxDepth ||
        rx_depth_ > kMaxDepth) {
      return false;
    }
    if (slot_words_ < kFrameWords || slot_words_ > kMaxSlotWords) {
      return false;
    }

    const uint64_t rx_base = static_cast<uint64_t>(RxBase());
    const uint64_t rx_bytes =
        static_cast<uint64_t>(rx_depth_) * slot_words_ * sizeof(uint32_t);
    return rx_base + rx_bytes <= span;
  }

  static uint32_t Next(uint32_t value, uint32_t depth) {
    return depth == 0 ? 0 : ((value + 1u) % depth);
  }

  uint32_t ReadReg(uint32_t offset) const {
    volatile uint32_t* reg =
        reinterpret_cast<volatile uint32_t*>(mmio_ + offset);
    return *reg;
  }

  void WriteReg(uint32_t offset, uint32_t value) {
    volatile uint32_t* reg =
        reinterpret_cast<volatile uint32_t*>(mmio_ + offset);
    *reg = value;
    __sync_synchronize();
  }

  void WriteSlot(uint32_t base, uint32_t index, const Frame& frame) {
    volatile uint32_t* slot = reinterpret_cast<volatile uint32_t*>(
        mmio_ + base + index * (slot_words_ * sizeof(uint32_t)));
    slot[0] = frame.word0;
    slot[1] = frame.word1;
    slot[2] = frame.word2;
    slot[3] = frame.word3;
    slot[4] = frame.word4;
    slot[5] = frame.word5;
    slot[6] = frame.word6;
    slot[7] = frame.word7;
    __sync_synchronize();
  }

  void ReadSlot(uint32_t base, uint32_t index, Frame* frame) const {
    volatile uint32_t* slot = reinterpret_cast<volatile uint32_t*>(
        mmio_ + base + index * (slot_words_ * sizeof(uint32_t)));
    frame->word0 = slot[0];
    frame->word1 = slot[1];
    frame->word2 = slot[2];
    frame->word3 = slot[3];
    frame->word4 = slot[4];
    frame->word5 = slot[5];
    frame->word6 = slot[6];
    frame->word7 = slot[7];
  }

  int fd_;
  void* map_base_;
  std::size_t map_len_;
  volatile uint8_t* mmio_;
  uint32_t tx_depth_;
  uint32_t rx_depth_;
  uint32_t slot_words_;
  Header observed_header_;
  std::string last_error_;
};
