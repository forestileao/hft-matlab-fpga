# Quartus Tutorial: DE10-Nano Terasic-Style Flow

This is the short practical version.

Use this repo the same way you would use a Terasic DE10-Nano HPS project:

- `quartus/de10_nano_hft/de10_nano_hft.qpf` is the Quartus project
- `quartus/de10_nano_hft/hft.qsys` is the Platform Designer system source
- `quartus/de10_nano_hft/de10_nano_hft.qsf` holds the board pin assignments and HPS DDR assignments

Do not hand-edit generated files under:

- `quartus/de10_nano_hft/hft/`
- `quartus/de10_nano_hft/hps_isw_handoff/`

## 1. Open The Project

Open:

- `quartus/de10_nano_hft/de10_nano_hft.qpf`

The project already uses:

- `TOP_LEVEL_ENTITY hft`

That is the generated Platform Designer system.

## 2. Open Platform Designer

In Quartus:

1. open `Tools`
2. open `Platform Designer`
3. open:
   - `quartus/de10_nano_hft/hft.qsys`

## 3. What You Should See

The important pieces are:

- `hps_0`
- `hft_trade_engine_avalon_mm_0`
- a clock source

The important connection is:

- `hps_0.h2f_lw_axi_master` -> `hft_trade_engine_avalon_mm_0.avalon_slave`

That is the ARM-to-FPGA MMIO path used by Linux.

## 4. What Not To Do

Do not assign pins for:

- `avs_address_i`
- `avs_read_i`
- `avs_write_i`
- `avs_writedata_i`
- `avs_readdata_o`
- `avs_waitrequest_o`

Those are internal Avalon-MM signals.

Only top-level exported ports need board pins.

## 5. Pins And DDR

This repo now follows the Terasic-style DE10-Nano HPS DDR constraint pattern:

- board pin locations are in `de10_nano_hft.qsf`
- HPS DDR electrical assignments are also in `de10_nano_hft.qsf`

You do not need to re-enter the DDR pins by hand if you keep this project structure.

## 6. Regenerate The System

After any edit to `hft.qsys`, regenerate the system.

From Quartus GUI:

1. save `hft.qsys`
2. click `Generate HDL`

From shell:

```bash
cd quartus/de10_nano_hft
/opt/intelFPGA/25.1/quartus/sopc_builder/bin/qsys-generate hft.qsys --synthesis=VHDL --output-directory=./hft
```

## 7. Compile

From shell:

```bash
cd quartus/de10_nano_hft
quartus_map de10_nano_hft -c de10_nano_hft
quartus_fit de10_nano_hft -c de10_nano_hft
quartus_asm de10_nano_hft -c de10_nano_hft
quartus_sta de10_nano_hft -c de10_nano_hft
```

The main output file is:

- `quartus/de10_nano_hft/output_files/de10_nano_hft.sof`

## 8. Program The Board

Use Quartus Programmer and load:

- `quartus/de10_nano_hft/output_files/de10_nano_hft.sof`

Program the FPGA, then boot Linux on the DE10-Nano as usual.

## 9. Linux Side

On the board, run the feed first:

```bash
cd /home/root
./fast_data_feed
```

Then run the receiver with the FPGA MMIO base:

```bash
cd /home/root
HFT_FPGA_MMIO_BASE=0xFF200000 ./fast_receiver
```

If the slave offset in Platform Designer is not `0x0000`, add the offset:

- offset `0x0000` -> `0xFF200000`
- offset `0x1000` -> `0xFF201000`

## 10. What To Edit In This Repo

Edit these:

- `quartus/de10_nano_hft/hft.qsys`
- `quartus/de10_nano_hft/de10_nano_hft.qsf`
- `quartus/hft_trade_engine_avalon_mm_hw.tcl`
- `vhdl/hft_trade_engine_avalon_mm.vhd`
- `vhdl/hft_trade_engine.vhd`
- `vhdl/trade_decision_core.vhd`

Do not edit generated output unless you are debugging generation itself.

## 11. If Something Breaks

The quickest clean rebuild is:

```bash
cd quartus/de10_nano_hft
rm -rf db incremental_db output_files simulation hft hft.sopcinfo hps_isw_handoff
/opt/intelFPGA/25.1/quartus/sopc_builder/bin/qsys-generate hft.qsys --synthesis=VHDL --output-directory=./hft
quartus_map de10_nano_hft -c de10_nano_hft
quartus_fit de10_nano_hft -c de10_nano_hft
```

That is the closest repo-local equivalent to restarting from a clean Terasic project flow.
