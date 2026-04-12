library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_generated_strategy_core is
end entity;

architecture tb of tb_generated_strategy_core is
  constant C_SLOT_WORDS : natural := 8;

  signal clk   : std_logic := '0';
  signal rst_n : std_logic := '0';

  signal snapshot_valid : std_logic := '0';
  signal snapshot_seq   : std_logic_vector(31 downto 0) := (others => '0');
  signal best_bid_px    : std_logic_vector(31 downto 0) := (others => '0');
  signal best_bid_qty   : std_logic_vector(31 downto 0) := (others => '0');
  signal best_ask_px    : std_logic_vector(31 downto 0) := (others => '0');
  signal best_ask_qty   : std_logic_vector(31 downto 0) := (others => '0');
  signal spread_1e4     : std_logic_vector(31 downto 0) := (others => '0');
  signal imbalance      : std_logic_vector(31 downto 0) := (others => '0');
  signal snapshot_ready : std_logic;

  signal rsp_valid : std_logic;
  signal rsp_data  : std_logic_vector(C_SLOT_WORDS * 32 - 1 downto 0);

  function f_word(frame : std_logic_vector; idx : natural) return std_logic_vector is
    variable lsb : natural := idx * 32;
  begin
    return frame(lsb + 31 downto lsb);
  end function;

  procedure push_snapshot(
    signal valid_s       : out std_logic;
    signal seq_s         : out std_logic_vector(31 downto 0);
    signal bid_px_s      : out std_logic_vector(31 downto 0);
    signal bid_qty_s     : out std_logic_vector(31 downto 0);
    signal ask_px_s      : out std_logic_vector(31 downto 0);
    signal ask_qty_s     : out std_logic_vector(31 downto 0);
    signal spread_s      : out std_logic_vector(31 downto 0);
    signal imbalance_s   : out std_logic_vector(31 downto 0);
    signal ready_s       : in  std_logic;
    constant seq_v       : in natural;
    constant bid_px_v    : in natural;
    constant bid_qty_v   : in natural;
    constant ask_px_v    : in natural;
    constant ask_qty_v   : in natural;
    constant spread_v    : in natural;
    constant imbalance_v : in integer
  ) is
  begin
    seq_s       <= std_logic_vector(to_unsigned(seq_v, 32));
    bid_px_s    <= std_logic_vector(to_unsigned(bid_px_v, 32));
    bid_qty_s   <= std_logic_vector(to_unsigned(bid_qty_v, 32));
    ask_px_s    <= std_logic_vector(to_unsigned(ask_px_v, 32));
    ask_qty_s   <= std_logic_vector(to_unsigned(ask_qty_v, 32));
    spread_s    <= std_logic_vector(to_unsigned(spread_v, 32));
    imbalance_s <= std_logic_vector(to_signed(imbalance_v, 32));
    valid_s     <= '1';
    wait until rising_edge(clk);
    while ready_s = '0' loop
      wait until rising_edge(clk);
    end loop;
    valid_s <= '0';
    wait until rising_edge(clk);
  end procedure;
begin
  clk <= not clk after 5 ns;

  dut : entity work.generated_strategy_core
    generic map (
      G_SLOT_WORDS          => C_SLOT_WORDS,
      G_IMBALANCE_THRESHOLD => 500,
      G_MAX_SPREAD_1E4      => 25000
    )
    port map (
      clk_i            => clk,
      rst_ni           => rst_n,
      snapshot_valid_i => snapshot_valid,
      snapshot_seq_i   => snapshot_seq,
      best_bid_px_i    => best_bid_px,
      best_bid_qty_i   => best_bid_qty,
      best_ask_px_i    => best_ask_px,
      best_ask_qty_i   => best_ask_qty,
      spread_1e4_i     => spread_1e4,
      imbalance_i      => imbalance,
      snapshot_ready_o => snapshot_ready,
      rsp_valid_o      => rsp_valid,
      rsp_data_o       => rsp_data,
      rsp_ready_i      => '1'
    );

  stim : process
  begin
    rst_n <= '0';
    wait for 40 ns;
    wait until rising_edge(clk);
    rst_n <= '1';
    wait until rising_edge(clk);

    push_snapshot(snapshot_valid, snapshot_seq, best_bid_px, best_bid_qty, best_ask_px, best_ask_qty, spread_1e4, imbalance, snapshot_ready,
                  1, 1850000, 2500, 1852000, 1200, 2000, 1300);
    assert rsp_valid = '1' report "valid BUY response missing" severity failure;
    assert f_word(rsp_data, 1) = x"00000001" report "valid BUY action mismatch" severity failure;

    push_snapshot(snapshot_valid, snapshot_seq, best_bid_px, best_bid_qty, best_ask_px, best_ask_qty, spread_1e4, imbalance, snapshot_ready,
                  2, 1852000, 2500, 1850000, 1200, 0, 1300);
    assert rsp_valid = '1' report "crossed response missing" severity failure;
    assert f_word(rsp_data, 1) = x"00000000" report "crossed book must force NOOP" severity failure;

    report "tb_generated_strategy_core PASSED" severity note;
    wait;
  end process;
end architecture;
