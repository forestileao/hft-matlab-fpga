# ARM-FPGA Shared Streaming Block

This document describes the shared-memory streaming block used by:
- ARM software (`cpp/src/fast_receiver.cpp`, `cpp/src/fpga_shared_stream.h`)
- FPGA bridge logic (`vhdl/arm_fpga_shared_stream_bridge.vhd`)
- FPGA decision wrapper (`vhdl/hft_trade_engine.vhd`, `vhdl/trade_decision_core.vhd`)
- HPS-facing bus wrapper (`vhdl/hft_trade_engine_avalon_mm.vhd`)

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
                |  - pack 256-bit event frame                  |
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
                                      |
                                      v
                +----------------------------------------------+
                |      trade_decision_core / hft_trade_engine  |
                |  - updates per-symbol order book             |
                |  - derives top-of-book signals               |
                |  - decides NOOP / BUY / SELL                 |
                |  - writes 256-bit response frame             |
                +----------------------------------------------+
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
| `0x028` | `SLOT_WORDS` | RO | words per slot (`8`) |
| `0x030` | `PERF_CTRL` | WO | write bit0 = `1` to reset telemetry counters |
| `0x034` | `PERF_CLOCK_HZ` | RO | FPGA telemetry clock, normally `50000000` |
| `0x038` | `PERF_COUNT` | RO | number of measured responses |
| `0x03C` | `PERF_LAST_LAT_CYCLES` | RO | most recent measured latency in FPGA clock cycles |
| `0x040` | `PERF_MIN_LAT_CYCLES` | RO | minimum measured latency in FPGA clock cycles |
| `0x044` | `PERF_MAX_LAT_CYCLES` | RO | maximum measured latency in FPGA clock cycles |
| `0x048` | `PERF_SUM_LAT_CYCLES_LO` | RO | low 32 bits of latency-cycle sum |
| `0x04C` | `PERF_SUM_LAT_CYCLES_HI` | RO | high 32 bits of latency-cycle sum |
| `0x050` | `PERF_CMD_STALL_CYCLES` | RO | cycles with command waiting for FPGA pipeline ready |
| `0x054` | `PERF_RSP_STALL_CYCLES` | RO | cycles with response blocked by RX-ring backpressure |
| `0x100` | `TX_SLOTS` | RW | TX slot memory base |
| dynamic | `RX_SLOTS` | RW | `RX_BASE = 0x100 + DEPTH * SLOT_WORDS * 4` |

Default with `DEPTH=64`, `SLOT_WORDS=8`:
- `TX_BASE = 0x100`
- `RX_BASE = 0x900`

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
MMIO base + 0x110  [TX slot 0 word4]
MMIO base + 0x114  [TX slot 0 word5]
MMIO base + 0x118  [TX slot 0 word6]
MMIO base + 0x11C  [TX slot 0 word7]
...
MMIO base + RX_BASE [RX slot 0 word0]
MMIO base + RX_BASE+4
...
MMIO base + RX_BASE+28
```

Slot size is fixed:
- `8 words * 4 bytes = 32 bytes`

Address formula:
- slot word address = `BASE + slot_index * 32 + word_index * 4`

## 6. Event Payload (Current C++ Mapping)

From `cpp/src/fast_receiver.cpp`:
- `word0`: sequence number (`SeqNo`)
- `word1`: `symbol_id`
- `word2`: fixed-point price (`price * 1e4`)
- `word3`: quantity
- `word4`: event type
  - `1 = UPSERT_LEVEL`
  - `2 = DELETE_LEVEL`
  - `3 = RESET_BOOK`
- `word5`: side code
  - `1 = BUY`
  - `2 = SELL`
- `word6`: level hint or order identifier placeholder
- `word7`: reserved

Current ARM symbol mapping:

- `0 = AAPL`
- `1 = MSFT`
- `2 = NVDA`
- `3 = GOOGL`
- `4 = TSLA`

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

## 8. Response Payload

The current FPGA decision wrapper returns a book-driven snapshot plus action:

- `word0`: echoed sequence number
- `word1`: action code
  - `0 = NOOP`
  - `1 = BUY`
  - `2 = SELL`
- `word2`: best bid price (`1e4` fixed point)
- `word3`: best bid quantity
- `word4`: best ask price (`1e4` fixed point)
- `word5`: best ask quantity
- `word6`: spread (`best_ask - best_bid`, `1e4` fixed point)
- `word7`: signed imbalance (`best_bid_qty - best_ask_qty`, two's complement)

This is the frame shape consumed by `fast_receiver.cpp` when it prints:

```text
[FPGA->ARM] seq=... action=BUY|SELL|NOOP best_bid_px_1e4=... best_bid_qty=... best_ask_px_1e4=... best_ask_qty=... spread_1e4=... imbalance=...
```

## 9. Performance Telemetry

The hardware benchmark reads the `PERF_*` registers to measure the FPGA-side processing path without TCP, FAST decode, sleeps, or per-message prints.

The latency counter starts when a command is accepted by the FPGA pipeline:

```text
cmd_valid = 1 and cmd_ready = 1
```

It stops when the matching response is accepted by the RX side of the MMIO bridge:

```text
rsp_valid = 1 and rsp_ready = 1
```

In the clean benchmark loop, the ARM drains RX continuously, so this is the internal FPGA processing latency. If RX fills up, `PERF_RSP_STALL_CYCLES` shows that backpressure separately.

Convert cycles to nanoseconds with:

```text
latency_ns = latency_cycles * 1_000_000_000 / PERF_CLOCK_HZ
```

For the DE10-Nano design, `PERF_CLOCK_HZ` is expected to be:

```text
50000000
```

The benchmark command is:

```bash
ssh root@192.168.7.1 'cd /home/root && HFT_FPGA_MMIO_BASE=0xFF200000 ./fpga_benchmark --mode full --messages 1000000 --warmup 10000'
```

The intended TCC pass checks are:

- `fpga_latency_jitter_ns < 1000`
- `throughput_msg_s >= 100000`
- `speedup_core >= 5.0`

## 10. How To Validate On Hardware

Minimal runtime checks:
1. Read `MAGIC` and `VERSION`.
2. Confirm `TX_DEPTH`, `RX_DEPTH`, `SLOT_WORDS`.
3. Reset queues with `CTRL.bit0`.
4. Reset telemetry with `PERF_CTRL.bit0`.
5. Push one frame:
   - write TX slot words
   - update `TX_HEAD`
6. Confirm FPGA consumption:
   - `TX_TAIL` advances.
7. Confirm FPGA response:
   - `STATUS.bit2` (`rx_has_data`) becomes `1`
   - `RX_HEAD` advances.
8. Confirm telemetry:
   - `PERF_COUNT` advances
   - `PERF_LAST_LAT_CYCLES`, `PERF_MIN_LAT_CYCLES`, `PERF_MAX_LAT_CYCLES`, and `PERF_SUM_LAT_CYCLES_*` are non-zero after a response.
9. Read RX slot words from `RX_BASE + RX_TAIL*32`.
10. Write updated `RX_TAIL`.
11. Confirm queue drained:
   - `STATUS.bit2` returns to `0`.

Quick interpretation of `STATUS`:
- bit0 `1`: ARM can send to TX ring now
- bit1 `1`: TX ring full
- bit2 `1`: RX has unread data
- bit3 `1`: RX ring full (FPGA backpressured)

## 11. Testbenches Available

Basic functional TB:
- `vhdl/tb_arm_fpga_shared_stream_bridge.vhd`
- command: `make vhdl-test`

Burst/FAST-like TB:
- `vhdl/tb_arm_fpga_shared_stream_bridge_fast.vhd`
- validates burst traffic, backpressure, wrap-around, and order
- command: `make vhdl-test-fast VHDL_STOP_TIME=200us`

End-to-end bridge + strategy TB:
- `vhdl/tb_hft_trade_engine.vhd`
- validates ARM-style TX publishes, FPGA decisions, RX responses, and action codes
- command: `make vhdl-test-engine`

Avalon-MM wrapper TB:
- `vhdl/tb_hft_trade_engine_avalon_mm.vhd`
- validates the board-facing bus wrapper used for HPS integration, including telemetry reset/readback
- command: `make vhdl-test-avalon`

Wave files:
- `vhdl/build/tb_arm_fpga_shared_stream_bridge.vcd`
- `vhdl/build/tb_arm_fpga_shared_stream_bridge_fast.vcd`
- `vhdl/build/tb_hft_trade_engine.vcd`
- `vhdl/build/tb_hft_trade_engine_avalon_mm.vcd`

## 12. Common Failure Patterns

If results look wrong, check:
1. Using fixed `0x500` RX base with non-default `DEPTH`.
2. Publishing `TX_HEAD` before writing all 8 slot words.
3. Updating `RX_TAIL` before reading all 8 RX words.
4. Writing more than ring capacity without draining (`DEPTH-1` effective usable entries).
5. Using `HFT_FPGA_MMIO_SPAN=0x1000` with the new 8-word default layout. The default span is now `0x2000`.
6. Mismatch between event type or `symbol_id` mapping on ARM and FPGA expectations.
7. Mismatch between strategy response frame format and what `fast_receiver.cpp` expects.
8. Running `fpga_benchmark` against an old `.sof` that does not include the `PERF_*` registers.
