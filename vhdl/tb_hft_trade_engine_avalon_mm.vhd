library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_hft_trade_engine_avalon_mm is
end entity;

architecture tb of tb_hft_trade_engine_avalon_mm is
  constant C_CLK_PERIOD : time := 10 ns;
  constant C_REG_MAGIC      : natural := 16#000#;
  constant C_REG_CTRL       : natural := 16#008#;
  constant C_REG_TX_HEAD    : natural := 16#010#;
  constant C_REG_PERF_CTRL  : natural := 16#030#;
  constant C_REG_PERF_CLOCK : natural := 16#034#;
  constant C_REG_PERF_COUNT : natural := 16#038#;
  constant C_REG_PERF_LAST  : natural := 16#03C#;
  constant C_REG_PERF_MIN   : natural := 16#040#;
  constant C_REG_PERF_MAX   : natural := 16#044#;
  constant C_REG_PERF_SUM_LO : natural := 16#048#;
  constant C_TX_BASE        : natural := 16#100#;

  signal clk_i             : std_logic := '0';
  signal rst_ni            : std_logic := '0';

  signal avs_chipselect_i  : std_logic := '0';
  signal avs_address_i     : std_logic_vector(10 downto 0) := (others => '0');
  signal avs_read_i        : std_logic := '0';
  signal avs_write_i       : std_logic := '0';
  signal avs_byteenable_i  : std_logic_vector(3 downto 0) := (others => '1');
  signal avs_writedata_i   : std_logic_vector(31 downto 0) := (others => '0');
  signal avs_readdata_o    : std_logic_vector(31 downto 0);
  signal avs_waitrequest_o : std_logic;

begin
  clk_i <= not clk_i after C_CLK_PERIOD / 2;

  dut : entity work.hft_trade_engine_avalon_mm
    generic map (
      G_ADDR_WIDTH     => 13,
      G_DEPTH          => 64,
      G_SLOT_WORDS     => 8,
      G_NUM_SYMBOLS    => 8,
      G_BOOK_DEPTH     => 8,
      G_TIMEOUT_CYCLES => 8
    )
    port map (
      clk_i             => clk_i,
      rst_ni            => rst_ni,
      avs_chipselect_i  => avs_chipselect_i,
      avs_address_i     => avs_address_i,
      avs_read_i        => avs_read_i,
      avs_write_i       => avs_write_i,
      avs_byteenable_i  => avs_byteenable_i,
      avs_writedata_i   => avs_writedata_i,
      avs_readdata_o    => avs_readdata_o,
      avs_waitrequest_o => avs_waitrequest_o
    );

  stim : process
    procedure avalon_idle is
    begin
      avs_chipselect_i <= '0';
      avs_read_i       <= '0';
      avs_write_i      <= '0';
      avs_address_i    <= (others => '0');
      avs_writedata_i  <= (others => '0');
    end procedure;

    procedure avalon_write(offset : natural; data : std_logic_vector(31 downto 0)) is
    begin
      avs_chipselect_i <= '1';
      avs_write_i      <= '1';
      avs_read_i       <= '0';
      avs_address_i    <= std_logic_vector(to_unsigned(offset / 4, avs_address_i'length));
      avs_writedata_i  <= data;
      wait until rising_edge(clk_i);
      while avs_waitrequest_o = '1' loop
        wait until rising_edge(clk_i);
      end loop;
      avalon_idle;
      wait until rising_edge(clk_i);
    end procedure;

    procedure avalon_read(offset : natural; variable data : out std_logic_vector(31 downto 0)) is
    begin
      avs_chipselect_i <= '1';
      avs_read_i       <= '1';
      avs_write_i      <= '0';
      avs_address_i    <= std_logic_vector(to_unsigned(offset / 4, avs_address_i'length));
      wait until rising_edge(clk_i);
      while avs_waitrequest_o = '1' loop
        wait until rising_edge(clk_i);
      end loop;
      data := avs_readdata_o;
      avalon_idle;
      wait until rising_edge(clk_i);
    end procedure;

    variable rdata_v : std_logic_vector(31 downto 0);
  begin
    -- ==========================
    -- 1) During reset, bridge must not hang
    -- ==========================
    rst_ni <= '0';
    wait for 3 * C_CLK_PERIOD;

    avs_chipselect_i <= '1';
    avs_read_i       <= '1';
    avs_address_i    <= (others => '0');
    wait for C_CLK_PERIOD;

    assert avs_waitrequest_o = '0'
      report "waitrequest must be low during reset"
      severity failure;

    avs_chipselect_i <= '0';
    avs_read_i       <= '0';
    wait for 2 * C_CLK_PERIOD;

    -- ==========================
    -- 2) Release reset
    -- ==========================
    rst_ni <= '1';
    wait for 3 * C_CLK_PERIOD;

    -- ==========================
    -- 3) Existing register map still responds
    -- ==========================
    avalon_read(C_REG_MAGIC, rdata_v);
    assert rdata_v = x"48465431"
      report "MAGIC register mismatch"
      severity failure;

    -- ==========================
    -- 4) Send one frame and verify performance counters
    -- ==========================
    avalon_write(C_REG_CTRL, x"00000001");
    avalon_write(C_REG_PERF_CTRL, x"00000001");

    avalon_write(C_TX_BASE + 0, x"00000001"); -- seq
    avalon_write(C_TX_BASE + 4, x"00000000"); -- symbol
    avalon_write(C_TX_BASE + 8, x"001C3A90"); -- price
    avalon_write(C_TX_BASE + 12, x"000003E8"); -- qty
    avalon_write(C_TX_BASE + 16, x"00000001"); -- upsert
    avalon_write(C_TX_BASE + 20, x"00000001"); -- buy
    avalon_write(C_TX_BASE + 24, x"00000000");
    avalon_write(C_TX_BASE + 28, x"00000000");
    avalon_write(C_REG_TX_HEAD, x"00000001");

    wait for 30 * C_CLK_PERIOD;

    avalon_read(C_REG_PERF_CLOCK, rdata_v);
    assert rdata_v = std_logic_vector(to_unsigned(50000000, 32))
      report "PERF_CLOCK_HZ mismatch"
      severity failure;

    avalon_read(C_REG_PERF_COUNT, rdata_v);
    assert unsigned(rdata_v) >= 1
      report "PERF_COUNT did not advance"
      severity failure;

    avalon_read(C_REG_PERF_LAST, rdata_v);
    assert unsigned(rdata_v) > 0
      report "PERF_LAST_LAT_CYCLES did not advance"
      severity failure;

    avalon_read(C_REG_PERF_MIN, rdata_v);
    assert unsigned(rdata_v) > 0
      report "PERF_MIN_LAT_CYCLES did not advance"
      severity failure;

    avalon_read(C_REG_PERF_MAX, rdata_v);
    assert unsigned(rdata_v) > 0
      report "PERF_MAX_LAT_CYCLES did not advance"
      severity failure;

    avalon_read(C_REG_PERF_SUM_LO, rdata_v);
    assert unsigned(rdata_v) > 0
      report "PERF_SUM_LAT_CYCLES_LO did not advance"
      severity failure;

    -- ==========================
    -- 5) Reset performance counters
    -- ==========================
    avalon_write(C_REG_PERF_CTRL, x"00000001");
    wait for 3 * C_CLK_PERIOD;
    avalon_read(C_REG_PERF_COUNT, rdata_v);
    assert rdata_v = x"00000000"
      report "PERF_COUNT did not reset"
      severity failure;

    -- ==========================
    -- 6) Finish
    -- ==========================
    assert false
      report "tb_hft_trade_engine_avalon_mm completed"
      severity note;

    wait;
  end process;
end architecture;
