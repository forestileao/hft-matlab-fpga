# ARM-FPGA Shared Streaming Block

This document describes the shared-memory streaming block used by:
- ARM software (`cpp/src/fast_receiver.cpp`, `cpp/src/fpga_shared_stream.h`)
- FPGA bridge logic (`vhdl/arm_fpga_shared_stream_bridge.vhd`)

It also explains how to validate results from registers/waveforms.

## 1. What This Block Does

The block is a dual-ring bridge:
- `TX ring`: ARM -> FPGA (commands/market frames)
- `RX ring`: FPGA -> ARM (results/responses)

Each ring is single-producer/single-consumer:
- ARM owns `TX_HEAD` and `RX_TAIL`
- FPGA owns `TX_TAIL` and `RX_HEAD`

This ownership avoids lock contention and keeps deterministic behavior.

## 2. Architecture (ASCII Graph)

```text
                +----------------------------------------------+
                |                  ARM (A9)                    |
                |                                              |
FAST TCP feed ->| fast_receiver.cpp                            |
                |  - decode FAST                               |
                |  - pack 128-bit frame                        |
                |  - write TX slot + TX_HEAD                   |
                |  - read RX slot + update RX_TAIL             |
                +---------------------+------------------------+
                                      |
                                      | MMIO (shared memory window)
                                      v
          +-----------------------------------------------------------+
          |        arm_fpga_shared_stream_bridge.vhd                  |
          |                                                           |
          |  Registers: MAGIC VERSION STATUS TX/RX HEAD/TAIL ...      |
          |                                                           |
          |  TX ring RAM                     RX ring RAM              |
          |  (ARM writes, FPGA reads)        (FPGA writes, ARM reads) |
          |                                                           |
          |   cmd_valid/cmd_data  --->  FPGA pipeline input           |
          |   rsp_valid/rsp_data  <---  FPGA pipeline output          |
          +-----------------------------------------------------------+
```

## 3. Ring Model

For both rings:
- `empty`: `head == tail`
- `full`: `next(head) == tail`
- `next(x) = (x + 1) mod DEPTH`

Producer sequence:
1. Check not full.
2. Write slot payload.
3. Publish by updating `head`.

Consumer sequence:
1. Check not empty.
2. Read slot payload.
3. Consume by updating `tail`.

## 4. Register Map

Offsets are byte offsets from MMIO base.

| Offset | Name | Access | Meaning |
|---|---|---|---|
| `0x000` | `MAGIC` | RO | `0x48465431` (`HFT1`) |
| `0x004` | `VERSION` | RO | protocol version (`1`) |
| `0x008` | `CTRL` | RW | bit0: soft reset pointers |
| `0x00C` | `STATUS` | RO | bit0 `can_send`, bit1 `tx_full`, bit2 `rx_has_data`, bit3 `rx_full` |
| `0x010` | `TX_HEAD` | RW | ARM publish pointer |
| `0x014` | `TX_TAIL` | RO | FPGA consume pointer |
| `0x018` | `RX_HEAD` | RO | FPGA publish pointer |
| `0x01C` | `RX_TAIL` | RW | ARM consume pointer |
| `0x020` | `TX_DEPTH` | RO | queue depth |
| `0x024` | `RX_DEPTH` | RO | queue depth |
| `0x028` | `SLOT_WORDS` | RO | words per slot (`4`) |
| `0x100` | `TX_SLOTS` | RW | TX slot memory base |
| dynamic | `RX_SLOTS` | RW | `RX_BASE = 0x100 + DEPTH * SLOT_WORDS * 4` |

Default with `DEPTH=64`, `SLOT_WORDS=4`:
- `TX_BASE = 0x100`
- `RX_BASE = 0x500`

## 5. Memory Layout (ASCII Graph)

```text
MMIO base + 0x000  [MAGIC]
MMIO base + 0x004  [VERSION]
...
MMIO base + 0x010  [TX_HEAD]
MMIO base + 0x014  [TX_TAIL]
MMIO base + 0x018  [RX_HEAD]
MMIO base + 0x01C  [RX_TAIL]
...
MMIO base + 0x100  [TX slot 0 word0]
MMIO base + 0x104  [TX slot 0 word1]
MMIO base + 0x108  [TX slot 0 word2]
MMIO base + 0x10C  [TX slot 0 word3]
...
MMIO base + RX_BASE [RX slot 0 word0]
MMIO base + RX_BASE+4
MMIO base + RX_BASE+8
MMIO base + RX_BASE+12
```

Slot size is fixed:
- `4 words * 4 bytes = 16 bytes`

Address formula:
- slot word address = `BASE + slot_index * 16 + word_index * 4`

## 6. Frame Payload (Current C++ Mapping)

From `cpp/src/fast_receiver.cpp`:
- `word0`: sequence number (`SeqNo`)
- `word1`: packed symbol+side
  - byte0..2 = first 3 symbol chars
  - byte3 = side code (`1=buy`, `2=sell`)
- `word2`: fixed-point price (`price * 1e4`)
- `word3`: quantity

## 7. Handshake Timing (ASCII)

ARM -> FPGA consume example:

```text
clk       _|-|_|-|_|-|_|-|_|-|_
TX_HEAD   ----n--------------------> n+1 (published by ARM)
TX_TAIL   ----m-----------> m+1      (consumed by FPGA)
cmd_valid ____/-----------\_________
cmd_ready ________/-------\_________
transfer          X (when valid=1 and ready=1)
```

FPGA -> ARM consume example:

```text
clk       _|-|_|-|_|-|_|-|_|-|_
RX_HEAD   ----k-----------> k+1      (published by FPGA)
RX_TAIL   ----j-----------------> j+1 (consumed by ARM after read)
rsp_valid ____/----\_________________
rsp_ready ---------/----\------------ (deasserts when RX full)
transfer      X
```

## 8. How To Validate On Hardware

Minimal runtime checks:
1. Read `MAGIC` and `VERSION`.
2. Confirm `TX_DEPTH`, `RX_DEPTH`, `SLOT_WORDS`.
3. Push one frame:
   - write TX slot words
   - update `TX_HEAD`
4. Confirm FPGA consumption:
   - `TX_TAIL` advances.
5. Confirm FPGA response:
   - `STATUS.bit2` (`rx_has_data`) becomes `1`
   - `RX_HEAD` advances.
6. Read RX slot words from `RX_BASE + RX_TAIL*16`.
7. Write updated `RX_TAIL`.
8. Confirm queue drained:
   - `STATUS.bit2` returns to `0`.

Quick interpretation of `STATUS`:
- bit0 `1`: ARM can send to TX ring now
- bit1 `1`: TX ring full
- bit2 `1`: RX has unread data
- bit3 `1`: RX ring full (FPGA backpressured)

## 9. Testbenches Available

Basic functional TB:
- `vhdl/tb_arm_fpga_shared_stream_bridge.vhd`
- command: `make vhdl-test`

Burst/FAST-like TB:
- `vhdl/tb_arm_fpga_shared_stream_bridge_fast.vhd`
- validates burst traffic, backpressure, wrap-around, and order
- command: `make vhdl-test-fast VHDL_STOP_TIME=200us`

Wave files:
- `vhdl/build/tb_arm_fpga_shared_stream_bridge.vcd`
- `vhdl/build/tb_arm_fpga_shared_stream_bridge_fast.vcd`

## 10. Common Failure Patterns

If results look wrong, check:
1. Using fixed `0x500` RX base with non-default `DEPTH`.
2. Publishing `TX_HEAD` before writing all 4 slot words.
3. Updating `RX_TAIL` before reading all 4 RX words.
4. Writing more than ring capacity without draining (`DEPTH-1` effective usable entries).
5. Endianness assumptions when decoding packed `word1`.
