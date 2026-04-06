# Quartus Tutorial: Pins, Reset, And HPS Bridge

This guide is only about the confusing Quartus parts:

- pin assignment
- reset wiring
- how the custom FPGA block connects to the HPS lightweight bridge

If you already understand the feed/receiver flow, this is the next piece you need.

## 0. Current Recommended Repo Flow

The most reliable flow in this repo is now:

- keep `quartus/de10_nano_hft/hft.qsys` as the Platform Designer system source
- let `qsys-generate` rebuild the generated `quartus/de10_nano_hft/hft/` output
- use the DE10-Nano HPS DDR pinout and calibrated termination style from a Terasic-generated project
- then run:
  - `quartus_map de10_nano_hft -c de10_nano_hft`
  - `quartus_fit de10_nano_hft -c de10_nano_hft`

This project was cleaned up to follow that pattern, and `quartus_fit` now completes successfully with the current `de10_nano_hft.qsf`.

Important:

- `quartus/de10_nano_hft/hft/` is generated output, not hand-edited source
- `quartus/de10_nano_hft/hft.qsys` is the file you edit when changing the Platform Designer system
- `quartus/de10_nano_hft/de10_nano_hft.qsf` now carries the board pin locations and the Terasic-style HPS DDR electrical assignments

## 1. The Most Important Idea

For this project, the custom block is **not supposed to go directly to board pins**.

The block:

- `vhdl/hft_trade_engine_avalon_mm.vhd`

is supposed to sit **inside the FPGA fabric** and be accessed by the HPS through an internal Avalon-MM connection.

That means:

- `avs_address_i`
- `avs_read_i`
- `avs_write_i`
- `avs_writedata_i`
- `avs_readdata_o`
- `avs_waitrequest_o`

are **internal bus signals**

and **should not be assigned to physical board pins**.

This is the main reason Quartus pin assignment feels strange here.

## 2. What Needs Pins And What Does Not

### Signals that usually do **not** need pin assignments

These are internal system signals:

- Avalon-MM slave bus signals
- internal reset connections
- internal clock routing inside Platform Designer
- HPS-to-FPGA bridge signals

For this project, that means the custom IP ports in:

- `hft_trade_engine_avalon_mm`

should usually be connected **inside Platform Designer**, not assigned in Pin Planner.

### Signals that **do** need pin assignments

These are external board-level signals, for example:

- board clock input
- LEDs
- switches
- push buttons
- external GPIO
- HPS fixed IO and DDR pins, if your top-level includes the HPS peripheral export ports

So the rule is:

- if a signal goes off-chip, it needs a pin
- if a signal stays inside the FPGA system, it does not

## 3. Why Your Current Top-Level Can Compile But Still Be Misleading

Your Quartus project currently uses:

- `TOP_LEVEL_ENTITY hft_trade_engine_avalon_mm`

in:

- `quartus/de10_nano_hft/de10_nano_hft.qsf`

That is fine for syntax checking and synthesis experiments.

But for the **real board design**, this is usually not the final top-level you want.

Why:

- `hft_trade_engine_avalon_mm` is only the custom slave block
- it does not create the HPS block
- it does not create the HPS lightweight bridge by itself
- it does not create the board-level clock/reset infrastructure by itself

So for a real DE10-Nano image, you usually want one of these:

1. a Platform Designer generated system as top-level, or
2. a board wrapper top-level that instantiates:
   - HPS system
   - your custom block
   - any external pins you want

## 4. Easiest Mental Model

Think of the design as three layers.

### Layer 1: Linux / ARM

Linux runs:

- `fast_data_feed`
- `fast_receiver`

and accesses a physical MMIO address like:

- `0xFF200000`

### Layer 2: HPS Lightweight Bridge

This is the internal path from HPS into FPGA fabric.

It carries Avalon-MM transactions from the ARM side into the FPGA side.

### Layer 3: Your Custom FPGA Block

This is:

- `hft_trade_engine_avalon_mm`

It receives Avalon-MM transactions from the bridge and exposes the shared-memory register map.

So the custom block belongs in Layer 3, not directly on package pins.

## 5. What To Do In Quartus

## 5.1 Open The Project

Open:

- `quartus/de10_nano_hft/de10_nano_hft.qpf`

This project is useful as a starting point, but expect to evolve it into a system-level project.

## 5.2 Decide Which Integration Style You Want

The practical recommendation is:

- use Platform Designer

because your block is already packaged as a custom Avalon-MM component:

- `quartus/hft_trade_engine_avalon_mm_hw.tcl`

## 5.3 Open Platform Designer

Inside Quartus:

1. open `Tools`
2. open `Platform Designer`
3. create a new system, or open an existing DE10-Nano HPS system if you already have one

## 5.4 Add Your Custom IP

Before adding it:

1. add the repo `quartus/` directory to the custom IP search path
2. refresh the IP catalog

Then instantiate:

- `HFT Trade Engine Avalon-MM`

## 5.5 Add Or Reuse The HPS Block

You need an HPS component in the system.

The important requirement is:

- the HPS lightweight FPGA master must be enabled

You want the HPS side to expose:

- `h2f_lw_axi_master`

That is the internal bus master that Linux uses through the lightweight bridge window.

## 5.6 Connect The Bus

Connect:

- `h2f_lw_axi_master`

to:

- `avalon_slave`

of:

- `hft_trade_engine_avalon_mm`

This is the most important connection in the whole system.

Without it, Linux cannot reach the FPGA registers.

## 6. Clock Wiring

Your custom block has:

- `clk_i`

The simplest rule is:

- connect it to the same FPGA-side clock domain used by the HPS lightweight bridge

In Platform Designer, this usually means:

- connect the custom IP `clock` input to the system clock you are already using for the HPS-facing interconnect

You do **not** usually assign `clk_i` directly in Pin Planner when using the custom component inside Platform Designer.

Instead:

- the system clock source is external
- Platform Designer routes that clock internally to the custom IP

## 7. Reset Wiring

Your custom block reset is:

- `rst_ni`

The `_ni` means:

- active low reset

In the custom IP file, this is exposed as a reset interface using:

- `reset_n`

So in Platform Designer, you should connect the block reset to a reset source that correctly drives an active-low reset input.

The easiest rule:

- if Platform Designer shows it as a reset sink, connect it normally
- trust the interface metadata to preserve the reset polarity

Conceptually, during reset:

- `rst_ni = 0`

and during normal operation:

- `rst_ni = 1`

## 8. Should You Use A Push Button Reset Pin

Not required for the first version.

The easiest path is:

- use the system reset already associated with the HPS / interconnect clock domain

You do **not** need to start by wiring a physical push-button reset unless you specifically want manual reset behavior.

So for now, the simpler answer is:

- use internal system reset
- do not worry about an external reset pin yet

## 9. Address Assignment

Once the bus is connected, assign a slave base offset in Platform Designer.

Recommended simple choices:

- `0x0000`
- `0x1000`

Then Linux base becomes:

- `0xFF200000 + offset`

Examples:

- offset `0x0000` -> `HFT_FPGA_MMIO_BASE=0xFF200000`
- offset `0x1000` -> `HFT_FPGA_MMIO_BASE=0xFF201000`

## 10. What To Put In Pin Planner

If you are doing the real HPS-integrated design, Pin Planner is **not** where you wire the custom Avalon bus.

Pin Planner is only for top-level external ports.

So:

- do not assign pins to `avs_*`
- do not assign pins to MMIO register signals
- do not assign pins to the internal bridge handshake signals

You only assign pins to:

- board clocks
- optional LEDs or debug GPIO
- HPS fixed IO and memory pins, if your system exports them at top level

## 11. What If Quartus Shows Unassigned Top-Level Ports

That usually means one of these is true:

1. you are compiling the custom block itself as the top-level
2. you have not yet wrapped it in a real board system
3. the Platform Designer generated system is not yet your actual top-level

That is why simply compiling:

- `hft_trade_engine_avalon_mm`

is not the same as having a finished board image.

## 12. Recommended Practical Path

If you want the least confusing path:

1. keep using `hft_trade_engine_avalon_mm` as a block, not as the final board design
2. build a Platform Designer system with:
   - HPS
   - system clock/reset
   - `HFT Trade Engine Avalon-MM`
3. connect HPS lightweight master to the custom slave
4. generate the system
5. make that generated system the real top-level or instantiate it in a small top wrapper
6. only then worry about board-level pin assignments

## 13. Simple Checklist While Looking At Quartus

When you open Quartus, ask these questions:

1. Is my custom IP inside Platform Designer, or am I compiling it standalone?
2. Is `h2f_lw_axi_master` enabled?
3. Is `avalon_slave` connected to that master?
4. Is the custom IP connected to a real clock?
5. Is the custom IP connected to a reset?
6. Did I assign an address offset?
7. Did I compute `HFT_FPGA_MMIO_BASE` from that offset?

If all seven are true, you are in the right direction.

## 14. What You Probably Need Next

The next useful artifact would be a real system-level DE10-Nano top design, not more low-level IP.

That means one of these:

- a Platform Designer `.qsys` system checked into the repo
- a top-level wrapper that instantiates that system

That is the point where pin assignment becomes much more concrete and much less mysterious.

## 15. Common HPS Warnings

When you instantiate the HPS block in Platform Designer, you may see warnings like these:

- `HPS model no longer supports simulation for HPS FPGA Bridges`
- `ODT is disabled`
- `set_interface_assignment: Interface "hps_io" does not exist`
- `hps_0.h2f_mpu_events must be exported, or connected to a matching conduit`

Here is what to do with them.

### 15.1 `HPS model no longer supports simulation for HPS FPGA Bridges`

This is not a hardware blocker.

It means the HPS bridge path is not fully modeled for simulation in the generated HPS simulation model.

For this project:

- ignore it for hardware bring-up
- do not treat it as a reason to stop

### 15.2 `ODT is disabled`

This is also not a first-bring-up blocker.

It is a DDR tuning suggestion, not a custom-IP integration error.

For this project:

- ignore it at first
- revisit only if you later debug DDR signal integrity issues

### 15.3 `hps_0.h2f_mpu_events must be exported`

This one should be fixed.

You have two options.

#### Option A: disable it

Best option if you are not using MPU event signals.

In Platform Designer:

1. double-click `hps_0`
2. look for FPGA events / MPU events / debug-related settings
3. disable `h2f_mpu_events` if possible

#### Option B: export it

If you cannot easily disable it:

1. go back to the Platform Designer canvas
2. find the `h2f_mpu_events` interface on `hps_0`
3. right-click it
4. choose `Export`
5. give it a name like `h2f_mpu_events_export`

Exporting is acceptable for now, but disabling unused signals is cleaner.

### 15.4 `Interface "hps_io" does not exist`

This usually means the HPS configuration is stale or inconsistent.

Typical causes:

- an old generated system is partially cached
- the HPS block configuration changed
- a script or assignment refers to an interface that no longer exists

The easiest fix is often:

1. delete `hps_0` from the Platform Designer system
2. save the system
3. add a fresh Cyclone V HPS block
4. re-enable only the things you really need
5. reconnect your custom IP

For the first working version, you usually only need:

- HPS fixed IO exported
- DDR memory interface exported
- `h2f_lw_axi_master` enabled
- the clock/reset used by the lightweight bridge path

## 16. Concrete Platform Designer Checklist

If you want the shortest path to a working system, do this:

1. add a fresh `Cyclone V HPS` block
2. enable the HPS lightweight FPGA master
   - `h2f_lw_axi_master`
3. add `HFT Trade Engine Avalon-MM`
4. connect:
   - `h2f_lw_axi_master` -> `avalon_slave`
   - system clock -> custom IP clock
   - system reset -> custom IP reset
5. assign a base offset like `0x0000` or `0x1000`
6. disable `h2f_mpu_events` if possible
7. if you cannot disable it, export it
8. regenerate the system

Then compute Linux base address as:

- `0xFF200000 + offset`

Examples:

- offset `0x0000` -> `HFT_FPGA_MMIO_BASE=0xFF200000`
- offset `0x1000` -> `HFT_FPGA_MMIO_BASE=0xFF201000`

## 17. Current Top-Level Choice

The Quartus project now uses the generated Platform Designer system directly:

- `TOP_LEVEL_ENTITY hft`

This rollback was intentional.

Using a wrapper around the HPS DDR interface caused Quartus to start treating the DDR pins like generic FPGA I/O, which led to misleading bank and I/O-standard errors.

So the current recommended setup is:

- use the generated `hft` system directly as the top-level
- assign pins to its exported ports directly
- avoid wrapping the HPS DDR interface unless you have a very specific reason

## 18. Pins Preassigned In The Quartus Project

The Quartus project file:

- [de10_nano_hft.qsf](/home/forestileao/Documents/code/hft-matlab-fpga/quartus/de10_nano_hft/de10_nano_hft.qsf)

now includes assignments for:

- `clk_clk -> PIN_V11`
- `memory_mem_a[0..12]`
- `memory_mem_ba[0..2]`
- `memory_mem_cas_n`
- `memory_mem_cke`
- `memory_mem_ck_n`
- `memory_mem_ck`
- `memory_mem_cs_n`
- `memory_mem_dm`
- `memory_mem_dq[0..7]`
- `memory_mem_dqs_n`
- `memory_mem_dqs`
- `memory_mem_odt`
- `memory_mem_ras_n`
- `memory_mem_reset_n`
- `memory_mem_we_n`
- `memory_oct_rzqin`

That is the exact set of pins exported by the currently generated HPS memory interface.

## 19. Important Caveat About The Current HPS DDR Setup

The generated HPS SDRAM configuration is still **x8**, not the DE10-Nano board's usual **x32** DDR3 layout.

You can see that in:

- [hft_inst.vhd](/home/forestileao/Documents/code/hft-matlab-fpga/quartus/de10_nano_hft/hft/hft_inst.vhd)
- [hps_sdram_p0_parameters.tcl](/home/forestileao/Documents/code/hft-matlab-fpga/quartus/de10_nano_hft/hft/synthesis/submodules/hps_sdram_p0_parameters.tcl)

Today it exports only:

- `DQ[7:0]`
- one `DQS` pair
- one `DM`

So the checked-in pin assignments now match the **currently generated** system, but they are not yet the final board-faithful DE10-Nano HPS DDR configuration.

For a fully correct DE10-Nano HPS build, the next Quartus step is to reconfigure the HPS SDRAM block to the board's real DDR3 geometry or import that HPS DDR setup from a known-good DE10-Nano reference design.
