library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_hft_trade_engine is
end entity;

architecture sim of tb_hft_trade_engine is
  constant C_ADDR_WIDTH : natural := 13;
  constant C_DEPTH      : natural := 4;
  constant C_SLOT_WORDS : natural := 8;

  constant C_REG_MAGIC   : natural := 16#000#;
  constant C_REG_VERSION : natural := 16#004#;
  constant C_REG_STATUS  : natural := 16#00C#;
  constant C_REG_TX_HEAD : natural := 16#010#;
  constant C_REG_TX_TAIL : natural := 16#014#;
  constant C_REG_RX_HEAD : natural := 16#018#;
  constant C_REG_RX_TAIL : natural := 16#01C#;

  constant C_TX_BASE : natural := 16#100#;
  constant C_RX_BASE : natural := C_TX_BASE + (C_DEPTH * C_SLOT_WORDS * 4);

  constant C_ACTION_NOOP : std_logic_vector(31 downto 0) := x"00000000";
  constant C_ACTION_BUY  : std_logic_vector(31 downto 0) := x"00000001";
  constant C_ACTION_SELL : std_logic_vector(31 downto 0) := x"00000002";

  type t_u32_array is array (natural range <>) of std_logic_vector(31 downto 0);

  function f_u32(v : natural) return std_logic_vector is
  begin
    return std_logic_vector(to_unsigned(v, 32));
  end function;

  function f_slot_addr(base : natural; slot : natural; lane : natural) return natural is
  begin
    return base + slot * C_SLOT_WORDS * 4 + lane * 4;
  end function;

  constant C_TX_W0 : t_u32_array(0 to 2) := (
    x"00000001",
    x"00000002",
    x"00000003"
  );

  constant C_TX_W1 : t_u32_array(0 to 2) := (
    x"00000000",
    x"00000000",
    x"00000000"
  );

  constant C_TX_W2 : t_u32_array(0 to 2) := (
    x"001C3A90",
    x"001C4260",
    x"001C4260"
  );

  constant C_TX_W3 : t_u32_array(0 to 2) := (
    x"000009C4",
    x"000004B0",
    x"00000C80"
  );

  constant C_TX_W4 : t_u32_array(0 to 2) := (
    x"00000001",
    x"00000001",
    x"00000001"
  );

  constant C_TX_W5 : t_u32_array(0 to 2) := (
    x"00000001",
    x"00000002",
    x"00000002"
  );

  constant C_TX_W6 : t_u32_array(0 to 2) := (
    x"00000000",
    x"00000000",
    x"00000000"
  );

  constant C_TX_W7 : t_u32_array(0 to 2) := (
    x"00000000",
    x"00000000",
    x"00000000"
  );

  constant C_EXPECT_ACTION : t_u32_array(0 to 2) := (
    C_ACTION_NOOP,
    C_ACTION_BUY,
    C_ACTION_SELL
  );

  constant C_EXPECT_W2 : t_u32_array(0 to 2) := (
    x"001C3A90",
    x"001C3A90",
    x"001C3A90"
  );

  constant C_EXPECT_W3 : t_u32_array(0 to 2) := (
    x"000009C4",
    x"000009C4",
    x"000009C4"
  );

  constant C_EXPECT_W4 : t_u32_array(0 to 2) := (
    x"00000000",
    x"001C4260",
    x"001C4260"
  );

  constant C_EXPECT_W5 : t_u32_array(0 to 2) := (
    x"00000000",
    x"000004B0",
    x"00000C80"
  );

  constant C_EXPECT_W6 : t_u32_array(0 to 2) := (
    x"00000000",
    x"000007D0",
    x"000007D0"
  );

  constant C_EXPECT_W7 : t_u32_array(0 to 2) := (
    x"000009C4",
    x"00000514",
    x"FFFFFD44"
  );

  signal clk     : std_logic := '0';
  signal rst_n   : std_logic := '0';

  signal mm_addr  : std_logic_vector(C_ADDR_WIDTH - 1 downto 0) := (others => '0');
  signal mm_wr    : std_logic := '0';
  signal mm_rd    : std_logic := '0';
  signal mm_wdata : std_logic_vector(31 downto 0) := (others => '0');
  signal mm_rdata : std_logic_vector(31 downto 0);
  signal mm_ready : std_logic;

  procedure mm_write(
    signal addr_s  : out std_logic_vector(C_ADDR_WIDTH - 1 downto 0);
    signal wr_s    : out std_logic;
    signal wdata_s : out std_logic_vector(31 downto 0);
    signal ready_s : in  std_logic;
    constant addr  : in  natural;
    constant data  : in  std_logic_vector(31 downto 0)
  ) is
  begin
    addr_s  <= std_logic_vector(to_unsigned(addr, C_ADDR_WIDTH));
    wdata_s <= data;
    wr_s    <= '1';
    wait until rising_edge(clk);
    while ready_s = '0' loop
      wait until rising_edge(clk);
    end loop;
    wr_s <= '0';
    wait until rising_edge(clk);
  end procedure;

  procedure mm_read(
    signal addr_s  : out std_logic_vector(C_ADDR_WIDTH - 1 downto 0);
    signal rd_s    : out std_logic;
    signal rdata_s : in  std_logic_vector(31 downto 0);
    signal ready_s : in  std_logic;
    constant addr  : in  natural;
    variable data  : out std_logic_vector(31 downto 0)
  ) is
  begin
    addr_s <= std_logic_vector(to_unsigned(addr, C_ADDR_WIDTH));
    rd_s   <= '1';
    wait until rising_edge(clk);
    while ready_s = '0' loop
      wait until rising_edge(clk);
    end loop;
    data := rdata_s;
    rd_s <= '0';
    wait until rising_edge(clk);
  end procedure;
begin
  clk <= not clk after 5 ns;

  dut : entity work.hft_trade_engine
    generic map (
      G_ADDR_WIDTH          => C_ADDR_WIDTH,
      G_DEPTH               => C_DEPTH,
      G_SLOT_WORDS          => C_SLOT_WORDS,
      G_IMBALANCE_THRESHOLD => 500,
      G_MAX_SPREAD_1E4      => 25000
    )
    port map (
      clk_i      => clk,
      rst_ni     => rst_n,
      mm_addr_i  => mm_addr,
      mm_wr_i    => mm_wr,
      mm_rd_i    => mm_rd,
      mm_wdata_i => mm_wdata,
      mm_rdata_o => mm_rdata,
      mm_ready_o => mm_ready
    );

  stim : process
    variable rd_val : std_logic_vector(31 downto 0);
  begin
    rst_n <= '0';
    wait for 40 ns;
    wait until rising_edge(clk);
    rst_n <= '1';
    wait until rising_edge(clk);

    mm_read(mm_addr, mm_rd, mm_rdata, mm_ready, C_REG_MAGIC, rd_val);
    assert rd_val = x"48465431" report "MAGIC mismatch" severity failure;
    mm_read(mm_addr, mm_rd, mm_rdata, mm_ready, C_REG_VERSION, rd_val);
    assert rd_val = x"00000001" report "VERSION mismatch" severity failure;

    for i in 0 to 2 loop
      mm_write(mm_addr, mm_wr, mm_wdata, mm_ready, f_slot_addr(C_TX_BASE, i, 0), C_TX_W0(i));
      mm_write(mm_addr, mm_wr, mm_wdata, mm_ready, f_slot_addr(C_TX_BASE, i, 1), C_TX_W1(i));
      mm_write(mm_addr, mm_wr, mm_wdata, mm_ready, f_slot_addr(C_TX_BASE, i, 2), C_TX_W2(i));
      mm_write(mm_addr, mm_wr, mm_wdata, mm_ready, f_slot_addr(C_TX_BASE, i, 3), C_TX_W3(i));
      mm_write(mm_addr, mm_wr, mm_wdata, mm_ready, f_slot_addr(C_TX_BASE, i, 4), C_TX_W4(i));
      mm_write(mm_addr, mm_wr, mm_wdata, mm_ready, f_slot_addr(C_TX_BASE, i, 5), C_TX_W5(i));
      mm_write(mm_addr, mm_wr, mm_wdata, mm_ready, f_slot_addr(C_TX_BASE, i, 6), C_TX_W6(i));
      mm_write(mm_addr, mm_wr, mm_wdata, mm_ready, f_slot_addr(C_TX_BASE, i, 7), C_TX_W7(i));
      mm_write(mm_addr, mm_wr, mm_wdata, mm_ready, C_REG_TX_HEAD, f_u32(i + 1));
    end loop;

    for i in 0 to 15 loop
      wait until rising_edge(clk);
    end loop;

    mm_read(mm_addr, mm_rd, mm_rdata, mm_ready, C_REG_TX_TAIL, rd_val);
    assert rd_val(15 downto 0) = x"0003" report "TX_TAIL should consume all three frames" severity failure;
    mm_read(mm_addr, mm_rd, mm_rdata, mm_ready, C_REG_RX_HEAD, rd_val);
    assert rd_val(15 downto 0) = x"0003" report "RX_HEAD should publish all three responses" severity failure;
    mm_read(mm_addr, mm_rd, mm_rdata, mm_ready, C_REG_STATUS, rd_val);
    assert rd_val(2) = '1' report "STATUS.rx_has_data should be high" severity failure;
    assert rd_val(3) = '1' report "STATUS.rx_full should be high at depth-1 occupancy" severity failure;

    for i in 0 to 2 loop
      mm_read(mm_addr, mm_rd, mm_rdata, mm_ready, f_slot_addr(C_RX_BASE, i, 0), rd_val);
      assert rd_val = C_TX_W0(i) report "RX response seq mismatch" severity failure;
      mm_read(mm_addr, mm_rd, mm_rdata, mm_ready, f_slot_addr(C_RX_BASE, i, 1), rd_val);
      assert rd_val = C_EXPECT_ACTION(i) report "RX action mismatch" severity failure;
      mm_read(mm_addr, mm_rd, mm_rdata, mm_ready, f_slot_addr(C_RX_BASE, i, 2), rd_val);
      assert rd_val = C_EXPECT_W2(i) report "RX best bid px mismatch" severity failure;
      mm_read(mm_addr, mm_rd, mm_rdata, mm_ready, f_slot_addr(C_RX_BASE, i, 3), rd_val);
      assert rd_val = C_EXPECT_W3(i) report "RX best bid qty mismatch" severity failure;
      mm_read(mm_addr, mm_rd, mm_rdata, mm_ready, f_slot_addr(C_RX_BASE, i, 4), rd_val);
      assert rd_val = C_EXPECT_W4(i) report "RX best ask px mismatch" severity failure;
      mm_read(mm_addr, mm_rd, mm_rdata, mm_ready, f_slot_addr(C_RX_BASE, i, 5), rd_val);
      assert rd_val = C_EXPECT_W5(i) report "RX best ask qty mismatch" severity failure;
      mm_read(mm_addr, mm_rd, mm_rdata, mm_ready, f_slot_addr(C_RX_BASE, i, 6), rd_val);
      assert rd_val = C_EXPECT_W6(i) report "RX spread mismatch" severity failure;
      mm_read(mm_addr, mm_rd, mm_rdata, mm_ready, f_slot_addr(C_RX_BASE, i, 7), rd_val);
      assert rd_val = C_EXPECT_W7(i) report "RX imbalance mismatch" severity failure;
      mm_write(mm_addr, mm_wr, mm_wdata, mm_ready, C_REG_RX_TAIL, f_u32(i + 1));
    end loop;

    mm_read(mm_addr, mm_rd, mm_rdata, mm_ready, C_REG_STATUS, rd_val);
    assert rd_val(2) = '0' report "STATUS.rx_has_data should clear after drain" severity failure;
    assert rd_val(3) = '0' report "STATUS.rx_full should clear after drain" severity failure;

    report "tb_hft_trade_engine PASSED" severity note;
    wait;
  end process;
end architecture sim;
