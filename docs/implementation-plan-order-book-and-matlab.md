# Implementation Plan: Order Book And MATLAB HDL Coder

## Goal

Move the project from the current message-by-message demo into a real market-data pipeline with:

1. HPS/ARM decoding the feed and translating events
2. FPGA maintaining a simplified order book
3. FPGA running a strategy on top of that book
4. MATLAB HDL Coder generating the strategy block by script

This plan intentionally keeps the existing HPS <-> FPGA bridge as the stable foundation:

- [cpp/src/fpga_shared_stream.h](/home/forestileao/Documents/code/hft-matlab-fpga/cpp/src/fpga_shared_stream.h)
- [cpp/src/fast_receiver.cpp](/home/forestileao/Documents/code/hft-matlab-fpga/cpp/src/fast_receiver.cpp)
- [vhdl/arm_fpga_shared_stream_bridge.vhd](/home/forestileao/Documents/code/hft-matlab-fpga/vhdl/arm_fpga_shared_stream_bridge.vhd)
- [docs/arm-fpga-shared-memory-stream.md](/home/forestileao/Documents/code/hft-matlab-fpga/docs/arm-fpga-shared-memory-stream.md)

## Current State

Today the working system is:

1. `fast_data_feed` publishes synthetic FAST messages
2. `fast_receiver` decodes them on the ARM side
3. ARM packs each event into a 128-bit frame
4. ARM sends the frame through the MMIO bridge
5. FPGA returns `NOOP`, `BUY`, or `SELL`

The current FPGA strategy is intentionally simple and stateless:

- [vhdl/trade_decision_core.vhd](/home/forestileao/Documents/code/hft-matlab-fpga/vhdl/trade_decision_core.vhd)
- [matlab/trade_decision_model.m](/home/forestileao/Documents/code/hft-matlab-fpga/matlab/trade_decision_model.m)

That is enough to prove the path works, but it is not yet an order-book-driven trading design.

## Recommended Architecture

The recommended split is:

- HPS handles FAST decoding and event normalization
- FPGA maintains the order book and derived market signals
- FPGA runs the trading strategy
- MATLAB HDL Coder generates the strategy block first, not the bridge or full order book

This is the best balance for the current repo because:

- the FAST path already works well on the ARM side
- the bridge is already implemented and hardware-validated
- the interesting acceleration work is the book update and strategy logic
- keeping the strategy as a separate block makes MATLAB integration much cleaner

## Why Not A Full Generic Sort

We should not start with a generic parallel sort such as a broad bubble-sort design.

Instead, the order book should use:

- fixed symbol count
- fixed depth per side
- ordered insertion
- removal by shift
- update-in-place when the price level already exists

That gives deterministic latency, simpler HDL, and much lower design risk.

## Scope Decision

The first order-book implementation should be:

- per symbol
- by price level, not per individual order
- fixed depth, for example `8` or `16` levels per side
- maintained incrementally

This is much more realistic for the FPGA and much more defendable for a TCC than trying to reproduce a full exchange matching engine.

## Phase 1: Define A Better Event Contract

The current frame is too small for a real book update path.

Current 4-word frame:

- `word0`: sequence number
- `word1`: symbol bytes plus side
- `word2`: price scaled by `1e4`
- `word3`: quantity

For the order-book path, the bridge payload should evolve into a richer fixed-width event frame, for example 8 words:

- `word0`: `seq_no`
- `word1`: `symbol_id`
- `word2`: `price_1e4`
- `word3`: `qty`
- `word4`: `event_type`
- `word5`: `side`
- `word6`: `order_id` or `level_hint`
- `word7`: reserved or timestamp fragment

Recommended event types:

- `ADD`
- `MODIFY`
- `CANCEL`
- `TRADE`
- `SNAPSHOT`
- `RESET_BOOK`

For the first version, `order_id` can stay unused and the design can operate as a level-based book.

### Deliverables

- update [docs/arm-fpga-shared-memory-stream.md](/home/forestileao/Documents/code/hft-matlab-fpga/docs/arm-fpga-shared-memory-stream.md)
- update [cpp/src/fpga_shared_stream.h](/home/forestileao/Documents/code/hft-matlab-fpga/cpp/src/fpga_shared_stream.h)
- update [cpp/src/fast_receiver.cpp](/home/forestileao/Documents/code/hft-matlab-fpga/cpp/src/fast_receiver.cpp)
- update bridge tests and VHDL tests for the new frame width

## Phase 2: Symbol Mapping On The HPS Side

The FPGA should not deal with strings such as `AAPL` or `NVDA`.

The ARM side should translate symbols into fixed IDs:

- `AAPL -> 0`
- `MSFT -> 1`
- `NVDA -> 2`
- `TSLA -> 3`

This keeps the FPGA logic small and deterministic.

### Deliverables

- add a symbol mapping table in [cpp/src/fast_receiver.cpp](/home/forestileao/Documents/code/hft-matlab-fpga/cpp/src/fast_receiver.cpp)
- document the `symbol_id` mapping in a new design doc or in the shared-stream protocol doc

## Phase 3: Implement The Order Book In VHDL

The new HDL block should maintain:

- `bid_price[level]`
- `bid_qty[level]`
- `ask_price[level]`
- `ask_qty[level]`

for each tracked symbol.

Recommended first parameters:

- `NUM_SYMBOLS = 4`
- `BOOK_DEPTH = 8`

Book rules:

- bids sorted descending
- asks sorted ascending
- update existing level if found
- insert by ordered shift if new level
- remove and compact if quantity becomes zero

This is an incremental ordered-array design, not a generic sorting engine.

### Suggested New HDL Files

- `vhdl/order_book_core.vhd`
- `vhdl/tb_order_book_core.vhd`

### Suggested Internal Outputs

- best bid price
- best bid quantity
- best ask price
- best ask quantity
- spread
- midprice
- imbalance

## Phase 4: Expose Book-Derived Signals

Before plugging MATLAB into the flow, the FPGA should already expose useful market signals.

Recommended derived metrics:

- `best_bid_px`
- `best_bid_qty`
- `best_ask_px`
- `best_ask_qty`
- `spread_1e4`
- `imbalance`

These can be exposed through:

- MMIO debug registers, or
- the RX response frame, or
- both

Using both is ideal for debug.

## Phase 5: Add A Manual HDL Strategy First

Before replacing anything with HDL Coder output, we should connect a hand-written strategy to the order book.

Example first rule:

- `BUY` if imbalance is above a threshold and spread is acceptable
- `SELL` if imbalance is below a threshold and spread is acceptable
- otherwise `NOOP`

This gives us:

- a known-good reference implementation
- a stable hardware interface for the later MATLAB-generated block

### Suggested New HDL Files

- `vhdl/book_strategy_core.vhd`
- `vhdl/tb_book_strategy_core.vhd`

## Phase 6: MATLAB HDL Coder Strategy

Once the order book and manual HDL strategy are stable, MATLAB should own only the strategy block first.

Recommended MATLAB files:

- `matlab/strategy.m`
- `matlab/strategy_tb.m`
- `matlab/hdl_generator.m`

### `strategy.m`

This should be a pure function with fixed-size, HDL-friendly inputs, for example:

```matlab
function action = strategy(best_bid_px, best_bid_qty, best_ask_px, best_ask_qty, imbalance)
```

Rules:

- fixed-size inputs only
- no strings
- no dynamic memory
- no unsupported toolbox-heavy constructs
- prefer fixed-point friendly arithmetic

### `hdl_generator.m`

This script should:

- configure HDL Coder programmatically
- set `strategy` as the DUT
- generate VHDL into a deterministic output folder
- avoid GUI-only steps

This makes the flow reproducible and scriptable.

## Phase 7: Replace Manual Strategy With Generated HDL

After MATLAB generation works, the generated block should replace the manual strategy behind a stable interface.

Recommended approach:

- keep the order-book block hand-written
- keep bridge and Avalon wrapper hand-written
- swap only the strategy submodule

This avoids turning the whole system into generated code and keeps debugging manageable.

## Phase 8: Hardware Validation On DE10-Nano

Once the new path is integrated:

1. rebuild Quartus
2. load the `.sof`
3. run the feed on the board
4. run the receiver with `HFT_FPGA_MMIO_BASE`
5. verify:
   - book updates are accepted
   - best bid/ask values make sense
   - strategy actions follow the intended rule

At this stage, debug outputs matter a lot. We should keep enough observability to confirm:

- symbol ID mapping
- event type mapping
- level insertion and removal
- top-of-book values
- final action decisions

## Performance Expectation

A simplified level-based book should be fast enough for the TCC.

Why:

- fixed depth
- fixed symbol count
- no generic sort of the entire data structure
- predictable update path
- easy pipelining

This is the right kind of FPGA acceleration:

- not “sort everything”
- but “update a bounded ordered structure with deterministic latency”

## Risks And Trade-Offs

### Risk 1: Event Contract Churn

If we change the frame shape too often, C++, docs, tests, and VHDL will drift.

Mitigation:

- freeze the event frame before starting the book implementation

### Risk 2: Overbuilding The First Book

Trying to support too many symbols, too many levels, or per-order tracking too early will slow the project down.

Mitigation:

- start with `4` symbols and `8` levels per side

### Risk 3: MATLAB HDL Mismatch

HDL Coder-friendly MATLAB is much more restricted than normal MATLAB.

Mitigation:

- keep `strategy.m` simple
- test it against the hand-written HDL behavior first

### Risk 4: Poor Debug Visibility

A book that updates internally but exposes no signals will be painful to validate.

Mitigation:

- expose top-of-book and derived metrics through MMIO or RX frames

## Recommended Implementation Order

1. freeze the new ARM -> FPGA event frame
2. update docs, C++, and bridge tests
3. add symbol ID mapping on ARM
4. implement `order_book_core.vhd`
5. add VHDL testbench for insert, update, cancel, wrap, and multi-symbol cases
6. expose best bid/ask and imbalance
7. implement a manual HDL strategy using those signals
8. validate on host simulation
9. validate on DE10-Nano
10. create `matlab/strategy.m` and `matlab/hdl_generator.m`
11. replace the manual strategy with generated HDL

## Concrete Near-Term Tasks

The next practical tasks in this repo should be:

1. create a new doc for the event frame and symbol IDs
2. widen the shared-stream frame from 4 words to 8 words
3. update the C++ sender path in [cpp/src/fast_receiver.cpp](/home/forestileao/Documents/code/hft-matlab-fpga/cpp/src/fast_receiver.cpp)
4. update [vhdl/arm_fpga_shared_stream_bridge.vhd](/home/forestileao/Documents/code/hft-matlab-fpga/vhdl/arm_fpga_shared_stream_bridge.vhd) test expectations if needed
5. add `order_book_core.vhd`
6. add `tb_order_book_core.vhd`
7. add a first manual strategy block driven by top-of-book signals

## Final Recommendation

For this project, the strongest and most realistic TCC path is:

- HPS decodes FAST and normalizes events
- FPGA maintains a simplified order book
- FPGA computes microstructure signals
- strategy starts in hand-written HDL
- MATLAB HDL Coder later takes over the strategy block

This keeps the hardware meaningful, the software useful, and the project scoped tightly enough to finish well.
