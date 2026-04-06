# DE10-Nano Tutorial: Feed -> FPGA -> Decision

This tutorial walks through the current prototype from first validation to board bring-up.

The goal is to run this path:

1. `fast_data_feed` generates sample market data
2. `fast_receiver` decodes FAST messages on the ARM side
3. decoded frames are written to the FPGA MMIO bridge
4. FPGA logic decides `NOOP`, `BUY`, or `SELL`
5. ARM reads the FPGA response and prints it

## 1. What Is Implemented

The current design is split into these pieces:

- `cpp/src/fast_data_feed.cpp`
  - TCP server on port `9001`
  - emits synthetic FAST messages
- `cpp/src/fast_receiver.cpp`
  - TCP client
  - decodes FAST messages
  - optionally writes frames into FPGA MMIO
  - reads back FPGA responses
- `vhdl/arm_fpga_shared_stream_bridge.vhd`
  - ARM/FPGA shared-memory ring bridge
- `vhdl/trade_decision_core.vhd`
  - simple strategy
  - `BUY` if side is buy and qty >= 2000
  - `SELL` if side is sell and qty >= 2000
  - otherwise `NOOP`
- `vhdl/hft_trade_engine.vhd`
  - bridge + decision core
- `vhdl/hft_trade_engine_avalon_mm.vhd`
  - board-facing Avalon-MM wrapper for Quartus / Platform Designer

## 2. Frame Format

ARM sends this 128-bit frame to FPGA:

- `word0`: sequence number
- `word1`: symbol + side
- `word2`: price scaled by `1e4`
- `word3`: quantity

FPGA returns:

- `word0`: echoed sequence number
- `word1`: action code
  - `0 = NOOP`
  - `1 = BUY`
  - `2 = SELL`
- `word2`: echoed `price_1e4`
- `word3`: echoed quantity

## 3. First Check: Run Everything In Simulation

Run the full host-side check:

```bash
make check
```

That runs:

- C++ wrapper test
- feed/receiver software smoke test
- bridge RTL test
- bridge stress test
- bridge + strategy test
- Avalon-MM wrapper test

Useful individual commands:

```bash
make cpp-smoke
make vhdl-test-engine
make vhdl-test-avalon
```

Expected result:

- `cpp-smoke` prints decoded market data
- `vhdl-test-engine` passes
- `vhdl-test-avalon` passes

## 4. Prepare The DE10-Nano Toolchain

The repo already contains simple commands for the tested DE10-Nano flow.

One-time setup:

```bash
make de10-setup
```

This:

- downloads the old Bootlin ARM toolchain
- pulls a sysroot from the board

Build the ARM binaries:

```bash
make de10-build
```

Copy them to the board:

```bash
make de10-copy
```

## 5. Run The Feed On The Board Without FPGA

Start the feed:

```bash
ssh root@192.168.7.1 'cd /home/root && ./fast_data_feed'
```

In another terminal, start the receiver:

```bash
ssh root@192.168.7.1 'cd /home/root && ./fast_receiver'
```

At this point you should see decoded entries such as:

```text
seq=10 sym=MSFT side=sell price=414.84 qty=2525
```

This confirms:

- the binaries run on the board
- the FAST feed path is healthy

## 6. Prepare The FPGA Block For Quartus

The board-facing top-level block is:

- `vhdl/hft_trade_engine_avalon_mm.vhd`

The Quartus custom component file is:

- `quartus/hft_trade_engine_avalon_mm_hw.tcl`

You can check that Quartus sees the component:

```bash
make quartus-ip-index
```

If that passes, Quartus can index the custom IP description.

## 7. Add The Block In Quartus / Platform Designer

You have two reasonable options.

### Option A: Plain HDL integration

Create a Quartus project and add:

- `vhdl/arm_fpga_shared_stream_bridge.vhd`
- `vhdl/trade_decision_core.vhd`
- `vhdl/hft_trade_engine.vhd`
- `vhdl/hft_trade_engine_avalon_mm.vhd`

Use:

- `hft_trade_engine_avalon_mm`

as the FPGA block that should connect to an HPS-visible Avalon-MM slave interface.

### Option B: Platform Designer integration

1. Open Platform Designer.
2. Add the repo `quartus/` directory as a custom IP search path.
3. Instantiate `HFT Trade Engine Avalon-MM`.
4. Connect:
   - `clock`
   - `reset`
   - `avalon_slave` to the HPS lightweight bridge master
5. Assign an address span of `0x1000`.
6. Pick a slave offset such as `0x0000` or `0x1000`.

## 8. Choose The Linux MMIO Base

On DE10-Nano Linux, the HPS lightweight bridge window is typically:

```text
0xFF200000
```

Use this formula:

```text
HFT_FPGA_MMIO_BASE = 0xFF200000 + platform_designer_offset
```

Examples:

- offset `0x0000` -> base `0xFF200000`
- offset `0x1000` -> base `0xFF201000`

## 9. Run Feed + FPGA On The Board

Start the feed:

```bash
ssh root@192.168.7.1 'cd /home/root && ./fast_data_feed'
```

Start the receiver with FPGA enabled:

```bash
ssh root@192.168.7.1 'cd /home/root && HFT_FPGA_MMIO_BASE=0xFF200000 ./fast_receiver'
```

Replace `0xFF200000` with your real assigned base if different.

Expected output when the FPGA block is connected and alive:

```text
[FPGA->ARM] seq=11 action=BUY price_1e4=1850000 qty=2500
```

If you only see decoded FAST messages and no `[FPGA->ARM]` lines, then:

- the receiver is running
- the feed is running
- but FPGA responses are not making it back yet

## 10. Stop The Programs

Use:

```bash
make de10-stop
```

Or manually:

```bash
ssh root@192.168.7.1 'killall fast_receiver fast_data_feed >/dev/null 2>&1 || true'
```

## 11. Debug Checklist

If software-only works but FPGA mode does not:

1. Confirm the bitstream loaded into the FPGA really contains `hft_trade_engine_avalon_mm`.
2. Confirm the Platform Designer slave offset.
3. Confirm `HFT_FPGA_MMIO_BASE` matches `0xFF200000 + offset`.
4. Confirm the bridge clock and reset are connected.
5. Confirm the HPS lightweight bridge is enabled in the board design.
6. Read the bridge registers first and verify `MAGIC = 0x48465431`.

## 12. Recommended Workflow

Use this order every time:

1. `make check`
2. `make quartus-ip-index`
3. `make de10-build`
4. `make de10-copy`
5. load FPGA image in Quartus flow
6. run `fast_data_feed`
7. run `fast_receiver` with `HFT_FPGA_MMIO_BASE`

## 13. Related Docs

- `README.md`
- `docs/arm-fpga-shared-memory-stream.md`
- `docs/de10-nano-quartus-integration.md`
