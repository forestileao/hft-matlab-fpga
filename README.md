# HFT FPGA Prototype

This repository is a small FPGA-assisted trading prototype for the Intel DE10-Nano.

At a high level, the project combines:

- `cpp/`: ARM-side programs that generate and receive a simplified FAST-style market data feed
- `vhdl/`: FPGA-side shared-stream bridge, a simple trade-decision engine, and testbenches
- `matlab/`: MATLAB project files and a matching placeholder strategy model for HDL-oriented work

The implemented pipeline today is:

- run a sample market data feed server
- receive and decode FAST messages
- translate each decoded entry into a normalized 256-bit book event
- forward that event through the FPGA MMIO shared-stream bridge
- have FPGA logic maintain a simplified per-symbol order book
- have FPGA logic return `NOOP`, `BUY`, or `SELL` plus top-of-book signals
- print those decisions back on the ARM side

For real board integration, the FPGA block is also wrapped as an Avalon-MM slave:

- `vhdl/hft_trade_engine_avalon_mm.vhd`
- `quartus/hft_trade_engine_avalon_mm_hw.tcl`

The current FPGA strategy is intentionally simple but now book-driven:

- update bid/ask levels per symbol inside the FPGA
- compute top-of-book spread and imbalance
- `BUY` when imbalance is at least `500` and spread is at most `2.5000`
- `SELL` when imbalance is at most `-500` and spread is at most `2.5000`
- otherwise `NOOP`

That rule is implemented in both:

- `vhdl/order_book_core.vhd`
- `vhdl/book_strategy_core.vhd`
- `vhdl/trade_decision_core.vhd`
- `matlab/strategy.m`
- `matlab/trade_decision_model.m`

This keeps the interface stable while leaving a clean place to swap in a future MATLAB-generated HDL block.

## Quick Test

Run the full host-side sanity pass:

```bash
make check
```

That runs:

- `cpp-test`: C++ MMIO wrapper test
- `cpp-smoke`: `fast_data_feed` + `fast_receiver` together in Docker
- `vhdl-test-all`: bridge-only, stress, order-book, end-to-end strategy, and Avalon wrapper simulations

If you want only the new end-to-end FPGA-path simulation:

```bash
make vhdl-test-engine
```

The VCD lands in `vhdl/build/tb_hft_trade_engine.vcd`.

If you want the board-facing Avalon wrapper simulation:

```bash
make vhdl-test-avalon
```

To sanity-check that Quartus can index the custom Platform Designer component:

```bash
make quartus-ip-index
```

To run the focused order-book testbench:

```bash
make vhdl-test-order-book
```

To run the MATLAB strategy self-check:

```bash
make matlab-test
```

To generate VHDL from MATLAB HDL Coder without using the GUI:

```bash
make matlab-hdl-generate
```

## DE10-Nano Target

The Makefile is preconfigured for:

- board: `root@192.168.7.1`
- remote home: `/home/root`
- local sysroot: `/tmp/de10nano-sysroot`

If your board IP changes, override `DE10_HOST`, for example:

```bash
make de10-build DE10_HOST=root@192.168.7.42
```

## One-Time Setup

Download the tested old ARM toolchain and pull a sysroot from the board:

```bash
make de10-setup
```

This does two things:

- downloads the older Bootlin ARM toolchain into `.toolchains/`
- copies `/lib`, `/usr/lib`, and `/usr/include` from the board into `/tmp/de10nano-sysroot`

Rerunning `make de10-sysroot` or `make de10-setup` refreshes the local sysroot copy from scratch.

## Build For The Board

```bash
make de10-build
```

Binaries are written to:

- `cpp/build-cross-de10/fast_receiver`
- `cpp/build-cross-de10/fast_data_feed`

## Check ABI

```bash
make de10-abi
```

Use this if you want to confirm the binary still matches the board runtime.

## Copy To The Board

```bash
make de10-copy
```

This copies both binaries to:

- `/home/root/fast_receiver`
- `/home/root/fast_data_feed`

## Smoke Test On The Board

```bash
make de10-smoke
```

This starts both programs briefly on the board and prints the running processes.

To run the receiver against FPGA logic loaded in the fabric, set the MMIO base on the board:

```bash
ssh root@192.168.7.1 'cd /home/root && HFT_FPGA_MMIO_BASE=0xFF200000 ./fast_receiver'
```

The default bridge span is now `0x2000` because the event/response slots are `8 x 32-bit` words.

When FPGA responses are present, the receiver prints lines like:

```text
[FPGA->ARM] seq=11 action=BUY best_bid_px_1e4=1850000 best_bid_qty=2500 best_ask_px_1e4=1852000 best_ask_qty=1200 spread_1e4=2000 imbalance=1300
```

## Stop The Programs On The Board

```bash
make de10-stop
```

## Manual Run

Start the feed:

```bash
ssh root@192.168.7.1 'cd /home/root && ./fast_data_feed'
```

Start the receiver:

```bash
ssh root@192.168.7.1 'cd /home/root && ./fast_receiver'
```

Stop both:

```bash
ssh root@192.168.7.1 'killall fast_receiver fast_data_feed >/dev/null 2>&1 || true'
```

## Useful Extra Commands

- `make cpp-test`
- `make cpp-smoke`
- `make cpp-test-armv7`
- `make quartus-ip-index`
- `make vhdl-test`
- `make vhdl-test-fast`
- `make vhdl-test-order-book`
- `make vhdl-test-engine`
- `make vhdl-test-avalon`
- `make vhdl-test-all`
- `make matlab-test`
- `make matlab-hdl-generate`

## Quartus Prime Lite

This repo now includes synthesizable HDL for the bridge plus decision engine, but it still does not include a complete Quartus project.

In Quartus Prime Lite, create a project and add:

- `vhdl/arm_fpga_shared_stream_bridge.vhd`
- `vhdl/trade_decision_core.vhd`
- `vhdl/hft_trade_engine.vhd`
- `vhdl/hft_trade_engine_avalon_mm.vhd`

Use:

- `hft_trade_engine` for the pure engine block
- `hft_trade_engine_avalon_mm` for the HPS-facing bus wrapper

If you are using Platform Designer, add the custom component:

- `quartus/hft_trade_engine_avalon_mm_hw.tcl`

The DE10-Nano integration steps and MMIO base-address formula are in:

- `docs/de10-nano-quartus-integration.md`

## Notes

- The stock Ubuntu ARM cross-compiler is too new for the DE10-Nano Angstrom image.
- The Makefile uses an older Bootlin toolchain automatically through `make de10-*`.
- `patches/mfast-armv7-boost-hash.patch` is still required for 32-bit ARM `mFAST` builds.
