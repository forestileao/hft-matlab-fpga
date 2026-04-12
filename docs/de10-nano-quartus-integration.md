# DE10-Nano Quartus Integration

This document explains how to expose the trading engine to Linux on the DE10-Nano through the HPS lightweight FPGA bridge.

## 1. Files To Add In Quartus

For a plain HDL project, the relevant source files are:

- `vhdl/arm_fpga_shared_stream_bridge.vhd`
- `vhdl/trade_decision_core.vhd`
- `vhdl/hft_trade_engine.vhd`
- `vhdl/hft_trade_engine_avalon_mm.vhd`

The board-facing top-level block for the HPS MMIO path is:

- `hft_trade_engine_avalon_mm`

## 2. Platform Designer Option

The repository also includes a custom component description:

- `quartus/hft_trade_engine_avalon_mm_hw.tcl`

You can validate that Quartus can index the component with:

```bash
make quartus-ip-index
```

In Platform Designer:

1. Add the repository `quartus/` directory to the custom IP search path.
2. Instantiate `HFT Trade Engine Avalon-MM`.
3. Connect:
   - `clock` to the system clock used by the HPS lightweight bridge
   - `reset` to the matching reset
   - `avalon_slave` to `h2f_lw_axi_master`
4. Assign an address span of `0x1000` bytes.

The component exposes the same register map documented in:

- `docs/arm-fpga-shared-memory-stream.md`

## 3. Linux MMIO Base Address

On the DE10-Nano, the HPS lightweight bridge is typically visible in Linux at:

- `0xFF200000`

If the component is assigned offset `0x00000` inside the lightweight bridge window, run:

```bash
HFT_FPGA_MMIO_BASE=0xFF200000 ./fast_receiver
```

If the component is assigned offset `0x01000`, run:

```bash
HFT_FPGA_MMIO_BASE=0xFF201000 ./fast_receiver
```

Formula:

- `HFT_FPGA_MMIO_BASE = 0xFF200000 + platform_designer_offset`

## 4. Software Contract

The ARM software still uses the same byte offsets:

- `0x000` magic
- `0x004` version
- `0x010` TX head
- `0x014` TX tail
- `0x018` RX head
- `0x01C` RX tail
- `0x100` TX slot memory
- `0x900` RX slot memory for the default `DEPTH=64`, `SLOT_WORDS=8`

That means the C++ receiver can use the exact same MMIO wrapper once the block is reachable at a valid physical base.

## 5. What Is Still Manual

This repo does not yet include:

- a complete DE10-Nano Quartus project
- HPS pin assignments
- a checked-in Platform Designer system for the whole board
- `.rbf`/`.sof` generation scripts

Those pieces are still board-project-specific, but the custom slave block and the Linux base-address formula are now defined.
