library ieee;
use ieee.std_logic_1164.all;

entity hft_trade_engine is
  generic (
    G_ADDR_WIDTH         : natural := 13;
    G_DEPTH              : natural := 64;
    G_SLOT_WORDS         : natural := 8;
    G_NUM_SYMBOLS        : natural := 8;
    G_BOOK_DEPTH         : natural := 8;
    G_IMBALANCE_THRESHOLD : natural := 500;
    G_MAX_SPREAD_1E4      : natural := 25000
  );
  port (
    clk_i     : in  std_logic;
    rst_ni    : in  std_logic;

    mm_addr_i  : in  std_logic_vector(G_ADDR_WIDTH - 1 downto 0);
    mm_wr_i    : in  std_logic;
    mm_rd_i    : in  std_logic;
    mm_wdata_i : in  std_logic_vector(31 downto 0);
    mm_rdata_o : out std_logic_vector(31 downto 0);
    mm_ready_o : out std_logic
  );
end entity;

architecture rtl of hft_trade_engine is
  signal cmd_valid_s : std_logic;
  signal cmd_data_s  : std_logic_vector(G_SLOT_WORDS * 32 - 1 downto 0);
  signal cmd_ready_s : std_logic;

  signal rsp_valid_s : std_logic;
  signal rsp_data_s  : std_logic_vector(G_SLOT_WORDS * 32 - 1 downto 0);
  signal rsp_ready_s : std_logic;
begin
  u_bridge : entity work.arm_fpga_shared_stream_bridge
    generic map (
      G_ADDR_WIDTH => G_ADDR_WIDTH,
      G_DEPTH      => G_DEPTH,
      G_SLOT_WORDS => G_SLOT_WORDS
    )
    port map (
      clk_i       => clk_i,
      rst_ni      => rst_ni,
      mm_addr_i   => mm_addr_i,
      mm_wr_i     => mm_wr_i,
      mm_rd_i     => mm_rd_i,
      mm_wdata_i  => mm_wdata_i,
      mm_rdata_o  => mm_rdata_o,
      mm_ready_o  => mm_ready_o,
      cmd_valid_o => cmd_valid_s,
      cmd_data_o  => cmd_data_s,
      cmd_ready_i => cmd_ready_s,
      rsp_valid_i => rsp_valid_s,
      rsp_data_i  => rsp_data_s,
      rsp_ready_o => rsp_ready_s
    );

  u_decision : entity work.trade_decision_core
    generic map (
      G_SLOT_WORDS          => G_SLOT_WORDS,
      G_NUM_SYMBOLS         => G_NUM_SYMBOLS,
      G_BOOK_DEPTH          => G_BOOK_DEPTH,
      G_IMBALANCE_THRESHOLD => G_IMBALANCE_THRESHOLD,
      G_MAX_SPREAD_1E4      => G_MAX_SPREAD_1E4
    )
    port map (
      clk_i       => clk_i,
      rst_ni      => rst_ni,
      cmd_valid_i => cmd_valid_s,
      cmd_data_i  => cmd_data_s,
      cmd_ready_o => cmd_ready_s,
      rsp_valid_o => rsp_valid_s,
      rsp_data_o  => rsp_data_s,
      rsp_ready_i => rsp_ready_s
    );
end architecture rtl;
