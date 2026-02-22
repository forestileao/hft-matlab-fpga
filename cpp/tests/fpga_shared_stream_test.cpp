#include "fpga_shared_stream.h"

#include <cerrno>
#include <cstdio>
#include <cstring>
#include <fcntl.h>
#include <iostream>
#include <string>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

namespace {

const std::size_t kSpan = 0x1000;
const uint32_t kRegMagic = 0x000;
const uint32_t kRegVersion = 0x004;
const uint32_t kRegTxHead = 0x010;
const uint32_t kRegTxTail = 0x014;
const uint32_t kRegRxHead = 0x018;
const uint32_t kRegRxTail = 0x01C;
const uint32_t kRegTxDepth = 0x020;
const uint32_t kRegRxDepth = 0x024;
const uint32_t kRegSlotWords = 0x028;
const uint32_t kTxBase = 0x100;
const uint32_t kRxBase = 0x500;

bool check(bool cond, const char* msg) {
  if (!cond) {
    std::cerr << "[FAIL] " << msg << "\n";
    return false;
  }
  return true;
}

struct BackingFile {
  int fd;
  std::string path;
};

bool create_backing_file(BackingFile* out) {
  if (out == nullptr) {
    return false;
  }

  char tmpl[] = "/tmp/fpga_shared_stream_test_XXXXXX";
  int fd = mkstemp(tmpl);
  if (fd < 0) {
    std::perror("mkstemp");
    return false;
  }

  if (ftruncate(fd, static_cast<off_t>(kSpan)) != 0) {
    std::perror("ftruncate");
    close(fd);
    unlink(tmpl);
    return false;
  }

  out->fd = fd;
  out->path = tmpl;
  return true;
}

void destroy_backing_file(const BackingFile& bf) {
  close(bf.fd);
  unlink(bf.path.c_str());
}

bool write32(const BackingFile& bf, uint32_t offset, uint32_t value) {
  ssize_t n = pwrite(bf.fd, &value, sizeof(value), static_cast<off_t>(offset));
  return n == static_cast<ssize_t>(sizeof(value));
}

bool read32(const BackingFile& bf, uint32_t offset, uint32_t* value) {
  if (value == nullptr) {
    return false;
  }
  ssize_t n = pread(bf.fd, value, sizeof(*value), static_cast<off_t>(offset));
  return n == static_cast<ssize_t>(sizeof(*value));
}

bool init_registers(const BackingFile& bf) {
  return write32(bf, kRegMagic, FpgaSharedStream::kMagic) &&
         write32(bf, kRegVersion, 1) &&
         write32(bf, kRegTxHead, 0) &&
         write32(bf, kRegTxTail, 0) &&
         write32(bf, kRegRxHead, 0) &&
         write32(bf, kRegRxTail, 0) &&
         write32(bf, kRegTxDepth, 4) &&
         write32(bf, kRegRxDepth, 4) &&
         write32(bf, kRegSlotWords, 4);
}

bool test_send_and_full(const BackingFile& bf, FpgaSharedStream* stream) {
  if (!check(stream->CanSend(), "initial CanSend should be true")) return false;
  if (!check(!stream->IsTxFull(), "initial TX should not be full")) return false;

  FpgaSharedStream::Frame f1{1, 0x11111111u, 0x22222222u, 0x33333333u};
  FpgaSharedStream::Frame f2{2, 0xAAAAAAAAu, 0xBBBBBBBBu, 0xCCCCCCCCu};
  FpgaSharedStream::Frame f3{3, 0x12345678u, 0x00000010u, 0x00000020u};
  FpgaSharedStream::Frame f4{4, 0x1u, 0x2u, 0x3u};

  if (!check(stream->Send(f1), "send f1")) return false;
  if (!check(stream->Send(f2), "send f2")) return false;
  if (!check(stream->Send(f3), "send f3")) return false;
  if (!check(!stream->Send(f4), "send f4 should fail when full")) return false;
  if (!check(stream->IsTxFull(), "TX should be full after 3 pushes at depth=4")) return false;

  uint32_t head = 0;
  if (!check(read32(bf, kRegTxHead, &head), "read TX_HEAD")) return false;
  if (!check(head == 3, "TX_HEAD should be 3")) return false;

  uint32_t slot0w0 = 0;
  uint32_t slot0w1 = 0;
  uint32_t slot0w2 = 0;
  uint32_t slot0w3 = 0;
  if (!check(read32(bf, kTxBase + 0, &slot0w0), "read tx slot0 word0")) return false;
  if (!check(read32(bf, kTxBase + 4, &slot0w1), "read tx slot0 word1")) return false;
  if (!check(read32(bf, kTxBase + 8, &slot0w2), "read tx slot0 word2")) return false;
  if (!check(read32(bf, kTxBase + 12, &slot0w3), "read tx slot0 word3")) return false;
  if (!check(slot0w0 == f1.word0 && slot0w1 == f1.word1 && slot0w2 == f1.word2 &&
                 slot0w3 == f1.word3,
             "slot0 payload mismatch")) {
    return false;
  }

  if (!check(write32(bf, kRegTxTail, 1), "simulate FPGA consume one frame")) return false;
  if (!check(stream->CanSend(), "CanSend should be true after TX_TAIL moves")) return false;

  return true;
}

bool test_receive_and_ack(const BackingFile& bf, FpgaSharedStream* stream) {
  const uint32_t off = kRxBase + 0;
  if (!check(write32(bf, off + 0, 0xDEADBEEFu), "write rx slot0 word0")) return false;
  if (!check(write32(bf, off + 4, 0x01020304u), "write rx slot0 word1")) return false;
  if (!check(write32(bf, off + 8, 0xAABBCCDDu), "write rx slot0 word2")) return false;
  if (!check(write32(bf, off + 12, 0x000001F4u), "write rx slot0 word3")) return false;
  if (!check(write32(bf, kRegRxHead, 1), "set RX_HEAD=1")) return false;
  if (!check(write32(bf, kRegRxTail, 0), "set RX_TAIL=0")) return false;

  if (!check(stream->HasRx(), "HasRx should be true")) return false;

  FpgaSharedStream::Frame rx{};
  if (!check(stream->Receive(&rx), "Receive should succeed")) return false;
  if (!check(rx.word0 == 0xDEADBEEFu, "rx word0 mismatch")) return false;
  if (!check(rx.word1 == 0x01020304u, "rx word1 mismatch")) return false;
  if (!check(rx.word2 == 0xAABBCCDDu, "rx word2 mismatch")) return false;
  if (!check(rx.word3 == 0x000001F4u, "rx word3 mismatch")) return false;

  uint32_t rx_tail = 0;
  if (!check(read32(bf, kRegRxTail, &rx_tail), "read RX_TAIL")) return false;
  if (!check(rx_tail == 1, "RX_TAIL should advance to 1")) return false;
  if (!check(!stream->HasRx(), "HasRx should be false after consume")) return false;
  if (!check(!stream->Receive(&rx), "Receive should fail on empty queue")) return false;

  return true;
}

}  // namespace

int main() {
  BackingFile bf{};
  if (!create_backing_file(&bf)) {
    return 1;
  }

  bool ok = init_registers(bf);
  if (!ok) {
    std::cerr << "Failed to initialize backing registers\n";
    destroy_backing_file(bf);
    return 1;
  }

  FpgaSharedStream stream;
  ok = stream.Open(0, kSpan, bf.path);
  ok = ok && check(stream.IsOpen(), "stream should be open");
  ok = ok && check(stream.Magic() == FpgaSharedStream::kMagic, "magic mismatch");
  ok = ok && check(stream.Version() == 1, "version mismatch");
  ok = ok && check(stream.TxDepth() == 4, "tx depth mismatch");
  ok = ok && check(stream.RxDepth() == 4, "rx depth mismatch");

  if (ok) {
    ok = test_send_and_full(bf, &stream);
  }
  if (ok) {
    ok = test_receive_and_ack(bf, &stream);
  }

  stream.Close();
  destroy_backing_file(bf);

  if (!ok) {
    return 1;
  }

  std::cout << "[PASS] fpga_shared_stream_test\n";
  return 0;
}

