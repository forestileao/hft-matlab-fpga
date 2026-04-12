library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_order_book_core is
end entity;

architecture tb of tb_order_book_core is
  constant C_SLOT_WORDS  : natural := 8;
  constant C_NUM_SYMBOLS : natural := 8;
  constant C_BOOK_DEPTH  : natural := 8;

  constant C_EVENT_UPSERT_LEVEL : natural := 1;
  constant C_EVENT_DELETE_LEVEL : natural := 2;

  constant C_SIDE_BUY  : natural := 1;
  constant C_SIDE_SELL : natural := 2;

  signal clk   : std_logic := '0';
  signal rst_n : std_logic := '0';

  signal evt_valid : std_logic := '0';
  signal evt_data  : std_logic_vector(C_SLOT_WORDS * 32 - 1 downto 0) := (others => '0');
  signal evt_ready : std_logic;

  signal snapshot_valid     : std_logic;
  signal snapshot_seq       : std_logic_vector(31 downto 0);
  signal snapshot_symbol_id : std_logic_vector(31 downto 0);
  signal best_bid_px        : std_logic_vector(31 downto 0);
  signal best_bid_qty       : std_logic_vector(31 downto 0);
  signal best_ask_px        : std_logic_vector(31 downto 0);
  signal best_ask_qty       : std_logic_vector(31 downto 0);
  signal spread_1e4         : std_logic_vector(31 downto 0);
  signal imbalance          : std_logic_vector(31 downto 0);

  procedure push_event(
    signal valid_s : out std_logic;
    signal data_s  : out std_logic_vector(C_SLOT_WORDS * 32 - 1 downto 0);
    signal ready_s : in  std_logic;
    constant seq_v : in natural;
    constant symbol_id_v : in natural;
    constant price_v : in natural;
    constant qty_v : in natural;
    constant event_type_v : in natural;
    constant side_v : in natural
  ) is
    variable frame_v : std_logic_vector(C_SLOT_WORDS * 32 - 1 downto 0) := (others => '0');
  begin
    frame_v(31 downto 0) := std_logic_vector(to_unsigned(seq_v, 32));
    frame_v(63 downto 32) := std_logic_vector(to_unsigned(symbol_id_v, 32));
    frame_v(95 downto 64) := std_logic_vector(to_unsigned(price_v, 32));
    frame_v(127 downto 96) := std_logic_vector(to_unsigned(qty_v, 32));
    frame_v(159 downto 128) := std_logic_vector(to_unsigned(event_type_v, 32));
    frame_v(191 downto 160) := std_logic_vector(to_unsigned(side_v, 32));
    data_s <= frame_v;
    valid_s <= '1';
    wait until rising_edge(clk);
    while ready_s = '0' loop
      wait until rising_edge(clk);
    end loop;
    valid_s <= '0';
    wait until rising_edge(clk);
  end procedure;
begin
  clk <= not clk after 5 ns;

  dut : entity work.order_book_core
    generic map (
      G_SLOT_WORDS  => C_SLOT_WORDS,
      G_NUM_SYMBOLS => C_NUM_SYMBOLS,
      G_BOOK_DEPTH  => C_BOOK_DEPTH
    )
    port map (
      clk_i                => clk,
      rst_ni               => rst_n,
      evt_valid_i          => evt_valid,
      evt_data_i           => evt_data,
      evt_ready_o          => evt_ready,
      snapshot_valid_o     => snapshot_valid,
      snapshot_seq_o       => snapshot_seq,
      snapshot_symbol_id_o => snapshot_symbol_id,
      best_bid_px_o        => best_bid_px,
      best_bid_qty_o       => best_bid_qty,
      best_ask_px_o        => best_ask_px,
      best_ask_qty_o       => best_ask_qty,
      spread_1e4_o         => spread_1e4,
      imbalance_o          => imbalance,
      snapshot_ready_i     => '1'
    );

  stim : process
  begin
    rst_n <= '0';
    wait for 40 ns;
    wait until rising_edge(clk);
    rst_n <= '1';
    wait until rising_edge(clk);

    push_event(evt_valid, evt_data, evt_ready, 1, 0, 1850000, 2500, C_EVENT_UPSERT_LEVEL, C_SIDE_BUY);
    assert snapshot_valid = '1' report "snapshot should assert after first event" severity failure;
    assert snapshot_seq = x"00000001" report "seq mismatch after buy" severity failure;
    assert snapshot_symbol_id = x"00000000" report "symbol mismatch after buy" severity failure;
    assert best_bid_px = x"001C3A90" report "best bid px mismatch after buy" severity failure;
    assert best_bid_qty = x"000009C4" report "best bid qty mismatch after buy" severity failure;
    assert best_ask_px = x"00000000" report "best ask should be empty after buy" severity failure;
    assert spread_1e4 = x"00000000" report "spread should be zero with one-sided book" severity failure;

    push_event(evt_valid, evt_data, evt_ready, 2, 0, 1852000, 1200, C_EVENT_UPSERT_LEVEL, C_SIDE_SELL);
    assert snapshot_seq = x"00000002" report "seq mismatch after sell" severity failure;
    assert best_bid_px = x"001C3A90" report "best bid px mismatch after sell" severity failure;
    assert best_ask_px = x"001C4260" report "best ask px mismatch after sell" severity failure;
    assert best_ask_qty = x"000004B0" report "best ask qty mismatch after sell" severity failure;
    assert spread_1e4 = x"000007D0" report "spread mismatch after sell" severity failure;
    assert imbalance = x"00000514" report "imbalance mismatch after sell, got " & to_hstring(imbalance) severity failure;

    push_event(evt_valid, evt_data, evt_ready, 3, 0, 1851000, 1800, C_EVENT_UPSERT_LEVEL, C_SIDE_BUY);
    assert snapshot_seq = x"00000003" report "seq mismatch after bid replace" severity failure;
    assert best_bid_px = x"001C3E78" report "best bid px mismatch after stronger bid" severity failure;
    assert best_bid_qty = x"00000708" report "best bid qty mismatch after stronger bid" severity failure;
    assert spread_1e4 = x"000003E8" report "spread mismatch after stronger bid" severity failure;
    assert imbalance = x"00000258" report "imbalance mismatch after stronger bid, got " & to_hstring(imbalance) severity failure;

    push_event(evt_valid, evt_data, evt_ready, 4, 0, 1850500, 999, C_EVENT_UPSERT_LEVEL, C_SIDE_SELL);
    assert snapshot_seq = x"00000004" report "seq mismatch after crossed ask" severity failure;
    assert best_bid_px = x"001C3E78" report "crossed ask should not change best bid" severity failure;
    assert best_ask_px = x"001C4260" report "crossed ask should be rejected" severity failure;
    assert best_ask_qty = x"000004B0" report "crossed ask should not change ask qty" severity failure;
    assert spread_1e4 = x"000003E8" report "spread should remain valid after crossed ask rejection" severity failure;

    push_event(evt_valid, evt_data, evt_ready, 5, 0, 1853000, 999, C_EVENT_UPSERT_LEVEL, C_SIDE_BUY);
    assert snapshot_seq = x"00000005" report "seq mismatch after crossed bid" severity failure;
    assert best_bid_px = x"001C3E78" report "crossed bid should be rejected" severity failure;
    assert best_ask_px = x"001C4260" report "crossed bid should not change best ask" severity failure;
    assert spread_1e4 = x"000003E8" report "spread should remain valid after crossed bid rejection" severity failure;

    push_event(evt_valid, evt_data, evt_ready, 6, 0, 1852000, 0, C_EVENT_DELETE_LEVEL, C_SIDE_SELL);
    assert snapshot_seq = x"00000006" report "seq mismatch after delete" severity failure;
    assert best_ask_px = x"00000000" report "best ask should clear after delete" severity failure;
    assert best_ask_qty = x"00000000" report "best ask qty should clear after delete" severity failure;
    assert spread_1e4 = x"00000000" report "spread should clear after delete" severity failure;

    report "tb_order_book_core PASSED" severity note;
    wait;
  end process;
end architecture;
