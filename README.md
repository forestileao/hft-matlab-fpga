# DE10-Nano Quick Start

This repository is a small FPGA trading-system prototype for the Intel DE10-Nano.

At a high level, the project combines:

- `cpp/`: ARM-side programs that generate and receive a simplified FAST-style market data feed
- `vhdl/`: FPGA-side shared-stream bridge logic and testbenches
- `matlab/`: MATLAB project files used for modeling and HDL-oriented work

The current software flow lets the ARM processor on the DE10-Nano:

- run a sample market data feed server
- receive and decode FAST messages
- optionally forward decoded frames through the FPGA MMIO shared-stream bridge

This README focuses on the shortest path to build and deploy the C++ binaries for the DE10-Nano target.

## Default Target

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

If you want the FPGA MMIO path enabled:

```bash
ssh root@192.168.7.1 'cd /home/root && HFT_FPGA_MMIO_BASE=0xFF200000 ./fast_receiver'
```

## Useful Extra Commands

Host-side C++ test:

```bash
make cpp-test
```

ARM emulation check:

```bash
make cpp-test-armv7
```

VHDL testbench:

```bash
make vhdl-test
make vhdl-test-fast
```

## Notes

- The stock Ubuntu ARM cross-compiler is too new for the DE10-Nano Angstrom image.
- The Makefile uses an older Bootlin toolchain automatically through `make de10-*`.
- `patches/mfast-armv7-boost-hash.patch` is still required for 32-bit ARM `mFAST` builds.
