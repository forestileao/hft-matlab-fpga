package require -exact qsys 15.0

set_module_property NAME hft_trade_engine_avalon_mm
set_module_property VERSION 1.0
set_module_property GROUP "Bridges and Adapters/Research"
set_module_property DISPLAY_NAME "HFT Trade Engine Avalon-MM"
set_module_property DESCRIPTION "ARM-to-FPGA shared-stream bridge plus simple trade decision engine"
set_module_property AUTHOR "OpenAI Codex"
set_module_property INSTANTIATE_IN_SYSTEM_MODULE true
set_module_property EDITABLE false

add_fileset QUARTUS_SYNTH QUARTUS_SYNTH generate_fileset
set_fileset_property QUARTUS_SYNTH TOP_LEVEL hft_trade_engine_avalon_mm

add_fileset SIM_VHDL SIM_VHDL generate_fileset
set_fileset_property SIM_VHDL TOP_LEVEL hft_trade_engine_avalon_mm

proc generate_fileset {entity_name} {
  add_fileset_file ../vhdl/arm_fpga_shared_stream_bridge.vhd VHDL PATH ../vhdl/arm_fpga_shared_stream_bridge.vhd
  add_fileset_file ../vhdl/order_book_core.vhd VHDL PATH ../vhdl/order_book_core.vhd
  add_fileset_file ../matlab/generated_hdl/codegen/strategy/hdlsrc/strategy.vhd VHDL PATH ../matlab/generated_hdl/codegen/strategy/hdlsrc/strategy.vhd
  add_fileset_file ../vhdl/generated_strategy_core.vhd VHDL PATH ../vhdl/generated_strategy_core.vhd
  add_fileset_file ../vhdl/trade_decision_core.vhd VHDL PATH ../vhdl/trade_decision_core.vhd
  add_fileset_file ../vhdl/hft_trade_engine.vhd VHDL PATH ../vhdl/hft_trade_engine.vhd
  add_fileset_file ../vhdl/hft_trade_engine_avalon_mm.vhd VHDL PATH ../vhdl/hft_trade_engine_avalon_mm.vhd TOP_LEVEL_FILE
}

add_parameter G_ADDR_WIDTH INTEGER 13
set_parameter_property G_ADDR_WIDTH DEFAULT_VALUE 13
set_parameter_property G_ADDR_WIDTH HDL_PARAMETER true
set_parameter_property G_ADDR_WIDTH DISPLAY_NAME "MMIO byte address width"
set_parameter_property G_ADDR_WIDTH ALLOWED_RANGES 13

add_parameter G_DEPTH INTEGER 64
set_parameter_property G_DEPTH DEFAULT_VALUE 64
set_parameter_property G_DEPTH HDL_PARAMETER true
set_parameter_property G_DEPTH DISPLAY_NAME "Ring depth"

add_parameter G_SLOT_WORDS INTEGER 8
set_parameter_property G_SLOT_WORDS DEFAULT_VALUE 8
set_parameter_property G_SLOT_WORDS HDL_PARAMETER true
set_parameter_property G_SLOT_WORDS DISPLAY_NAME "Words per slot"
set_parameter_property G_SLOT_WORDS ALLOWED_RANGES 8

add_parameter G_NUM_SYMBOLS INTEGER 8
set_parameter_property G_NUM_SYMBOLS DEFAULT_VALUE 8
set_parameter_property G_NUM_SYMBOLS HDL_PARAMETER true
set_parameter_property G_NUM_SYMBOLS DISPLAY_NAME "Tracked symbol count"

add_parameter G_BOOK_DEPTH INTEGER 8
set_parameter_property G_BOOK_DEPTH DEFAULT_VALUE 8
set_parameter_property G_BOOK_DEPTH HDL_PARAMETER true
set_parameter_property G_BOOK_DEPTH DISPLAY_NAME "Levels per side"

add_parameter G_IMBALANCE_THRESHOLD INTEGER 500
set_parameter_property G_IMBALANCE_THRESHOLD DEFAULT_VALUE 500
set_parameter_property G_IMBALANCE_THRESHOLD HDL_PARAMETER true
set_parameter_property G_IMBALANCE_THRESHOLD DISPLAY_NAME "Imbalance threshold"

add_parameter G_MAX_SPREAD_1E4 INTEGER 25000
set_parameter_property G_MAX_SPREAD_1E4 DEFAULT_VALUE 25000
set_parameter_property G_MAX_SPREAD_1E4 HDL_PARAMETER true
set_parameter_property G_MAX_SPREAD_1E4 DISPLAY_NAME "Maximum spread (1e4 fixed point)"

add_interface clock clock sink
set_interface_property clock ENABLED true
add_interface_port clock clk_i clk Input 1

add_interface reset reset sink
set_interface_property reset associatedClock clock
set_interface_property reset synchronousEdges DEASSERT
set_interface_property reset ENABLED true
add_interface_port reset rst_ni reset_n Input 1

add_interface avalon_slave avalon end
set_interface_property avalon_slave addressUnits WORDS
set_interface_property avalon_slave associatedClock clock
set_interface_property avalon_slave associatedReset reset
set_interface_property avalon_slave bitsPerSymbol 8
set_interface_property avalon_slave burstOnBurstBoundariesOnly false
set_interface_property avalon_slave explicitAddressSpan 0
set_interface_property avalon_slave holdTime 0
set_interface_property avalon_slave linewrapBursts false
set_interface_property avalon_slave maximumPendingReadTransactions 0
set_interface_property avalon_slave maximumPendingWriteTransactions 0
set_interface_property avalon_slave readLatency 0
set_interface_property avalon_slave readWaitTime 1
set_interface_property avalon_slave setupTime 0
set_interface_property avalon_slave timingUnits Cycles
set_interface_property avalon_slave writeWaitTime 1
set_interface_property avalon_slave ENABLED true
set_interface_property avalon_slave addressSpan 2048

add_interface_port avalon_slave avs_chipselect_i chipselect Input 1
add_interface_port avalon_slave avs_address_i address Input 11
add_interface_port avalon_slave avs_read_i read Input 1
add_interface_port avalon_slave avs_write_i write Input 1
add_interface_port avalon_slave avs_byteenable_i byteenable Input 4
add_interface_port avalon_slave avs_writedata_i writedata Input 32
add_interface_port avalon_slave avs_readdata_o readdata Output 32
add_interface_port avalon_slave avs_waitrequest_o waitrequest Output 1

set_interface_assignment avalon_slave embeddedsw.configuration.isFlash 0
set_interface_assignment avalon_slave embeddedsw.configuration.isMemoryDevice 0
set_interface_assignment avalon_slave embeddedsw.configuration.isNonVolatileStorage 0
set_interface_assignment avalon_slave embeddedsw.configuration.isPrintableDevice 0
