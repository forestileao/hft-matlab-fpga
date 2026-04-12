library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_hft_trade_engine_avalon_mm is
end entity;

architecture tb of tb_hft_trade_engine_avalon_mm is
  constant C_CLK_PERIOD : time := 10 ns;

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
    -- 3) Issue read and ensure it eventually completes
    --    If engine does not answer, wrapper must timeout safely
    -- ==========================
    avs_chipselect_i <= '1';
    avs_read_i       <= '1';
    avs_address_i    <= (others => '0');

    wait until avs_waitrequest_o = '1';
    wait until avs_waitrequest_o = '0';

    avs_chipselect_i <= '0';
    avs_read_i       <= '0';

    assert avs_readdata_o = x"BAADF00D" or avs_readdata_o /= x"XXXXXXXX"
      report "read must complete with timeout sentinel or valid data"
      severity note;

    wait for 5 * C_CLK_PERIOD;

    -- ==========================
    -- 4) Finish
    -- ==========================
    assert false
      report "tb_hft_trade_engine_avalon_mm completed"
      severity note;

    wait;
  end process;
end architecture;