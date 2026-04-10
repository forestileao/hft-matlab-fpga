library ieee;
use ieee.std_logic_1164.all;

entity trade_decision_core is
  generic (
    G_SLOT_WORDS          : natural := 8;
    G_NUM_SYMBOLS         : natural := 8;
    G_BOOK_DEPTH          : natural := 8;
    G_IMBALANCE_THRESHOLD : natural := 500;
    G_MAX_SPREAD_1E4      : natural := 25000
  );
  port (
    clk_i : in std_logic;
    rst_ni : in std_logic;

    cmd_valid_i : in std_logic;
    cmd_data_i  : in std_logic_vector(G_SLOT_WORDS * 32 - 1 downto 0);
    cmd_ready_o : out std_logic;

    rsp_valid_o : out std_logic;
    rsp_data_o  : out std_logic_vector(G_SLOT_WORDS * 32 - 1 downto 0);
    rsp_ready_i : in std_logic
  );
end entity;

architecture rtl of trade_decision_core is
  signal snapshot_valid_s     : std_logic;
  signal snapshot_seq_s       : std_logic_vector(31 downto 0);
  signal snapshot_symbol_id_s : std_logic_vector(31 downto 0);
  signal best_bid_px_s        : std_logic_vector(31 downto 0);
  signal best_bid_qty_s       : std_logic_vector(31 downto 0);
  signal best_ask_px_s        : std_logic_vector(31 downto 0);
  signal best_ask_qty_s       : std_logic_vector(31 downto 0);
  signal spread_1e4_s         : std_logic_vector(31 downto 0);
  signal imbalance_s          : std_logic_vector(31 downto 0);
  signal snapshot_ready_s     : std_logic;
begin
  u_order_book : entity work.order_book_core
    generic map (
      G_SLOT_WORDS  => G_SLOT_WORDS,
      G_NUM_SYMBOLS => G_NUM_SYMBOLS,
      G_BOOK_DEPTH  => G_BOOK_DEPTH
    )
    port map (
      clk_i                => clk_i,
      rst_ni               => rst_ni,
      evt_valid_i          => cmd_valid_i,
      evt_data_i           => cmd_data_i,
      evt_ready_o          => cmd_ready_o,
      snapshot_valid_o     => snapshot_valid_s,
      snapshot_seq_o       => snapshot_seq_s,
      snapshot_symbol_id_o => snapshot_symbol_id_s,
      best_bid_px_o        => best_bid_px_s,
      best_bid_qty_o       => best_bid_qty_s,
      best_ask_px_o        => best_ask_px_s,
      best_ask_qty_o       => best_ask_qty_s,
      spread_1e4_o         => spread_1e4_s,
      imbalance_o          => imbalance_s,
      snapshot_ready_i     => snapshot_ready_s
    );

  u_strategy : entity work.generated_strategy_core
    generic map (
      G_SLOT_WORDS          => G_SLOT_WORDS,
      G_IMBALANCE_THRESHOLD => G_IMBALANCE_THRESHOLD,
      G_MAX_SPREAD_1E4      => G_MAX_SPREAD_1E4
    )
    port map (
      clk_i            => clk_i,
      rst_ni           => rst_ni,
      snapshot_valid_i => snapshot_valid_s,
      snapshot_seq_i   => snapshot_seq_s,
      best_bid_px_i    => best_bid_px_s,
      best_bid_qty_i   => best_bid_qty_s,
      best_ask_px_i    => best_ask_px_s,
      best_ask_qty_i   => best_ask_qty_s,
      spread_1e4_i     => spread_1e4_s,
      imbalance_i      => imbalance_s,
      snapshot_ready_o => snapshot_ready_s,
      rsp_valid_o      => rsp_valid_o,
      rsp_data_o       => rsp_data_o,
      rsp_ready_i      => rsp_ready_i
    );
end architecture rtl;
