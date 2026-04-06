library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_hft_trade_engine_avalon_mm is
end entity;

architecture tb of tb_hft_trade_engine_avalon_mm is
  constant C_ADDR_WIDTH : natural := 12;
  constant C_DEPTH      : natural := 4;
  constant C_SLOT_WORDS : natural := 4;

  constant C_REG_MAGIC_W   : natural := 16#000# / 4;
  constant C_REG_VERSION_W : natural := 16#004# / 4;
  constant C_REG_STATUS_W  : natural := 16#00C# / 4;
  constant C_REG_TX_HEAD_W : natural := 16#010# / 4;
  constant C_REG_TX_TAIL_W : natural := 16#014# / 4;
  constant C_REG_RX_HEAD_W : natural := 16#018# / 4;
  constant C_REG_RX_TAIL_W : natural := 16#01C# / 4;

  constant C_TX_BASE_W : natural := 16#100# / 4;
  constant C_RX_BASE_W : natural := C_TX_BASE_W + (C_DEPTH * C_SLOT_WORDS);

  constant C_ACTION_NOOP : std_logic_vector(31 downto 0) := x"00000000";
  constant C_ACTION_BUY  : std_logic_vector(31 downto 0) := x"00000001";
  constant C_ACTION_SELL : std_logic_vector(31 downto 0) := x"00000002";

  type t_u32_array is array (natural range <>) of std_logic_vector(31 downto 0);

  function f_u32(v : natural) return std_logic_vector is
  begin
    return std_logic_vector(to_unsigned(v, 32));
  end function;

  function f_pack_symbol_side(
    symbol_3  : string(1 to 3);
    side_code : natural
  ) return std_logic_vector is
    variable packed : unsigned(31 downto 0) := (others => '0');
  begin
    packed(7 downto 0)   := to_unsigned(character'pos(symbol_3(1)), 8);
    packed(15 downto 8)  := to_unsigned(character'pos(symbol_3(2)), 8);
    packed(23 downto 16) := to_unsigned(character'pos(symbol_3(3)), 8);
    packed(31 downto 24) := to_unsigned(side_code, 8);
    return std_logic_vector(packed);
  end function;

  function f_slot_addr_w(base_w : natural; slot : natural; lane : natural) return natural is
  begin
    return base_w + slot * C_SLOT_WORDS + lane;
  end function;

  constant C_TX_W0 : t_u32_array(0 to 2) := (
    x"00000015",
    x"00000016",
    x"00000017"
  );

  constant C_TX_W1 : t_u32_array(0 to 2) := (
    f_pack_symbol_side("AAP", 1),
    f_pack_symbol_side("MSF", 2),
    f_pack_symbol_side("GOO", 1)
  );

  constant C_TX_W2 : t_u32_array(0 to 2) := (
    x"001C3A90",
    x"003F52F0",
    x"0019F0A0"
  );

  constant C_TX_W3 : t_u32_array(0 to 2) := (
    x"00000BB8",
    x"00000AF0",
    x"00000258"
  );

  constant C_EXPECT_ACTION : t_u32_array(0 to 2) := (
    C_ACTION_BUY,
    C_ACTION_SELL,
    C_ACTION_NOOP
  );

  signal clk    : std_logic := '0';
  signal rst_n  : std_logic := '0';

  signal avs_chipselect  : std_logic := '0';
  signal avs_address     : std_logic_vector(C_ADDR_WIDTH - 3 downto 0) := (others => '0');
  signal avs_read        : std_logic := '0';
  signal avs_write       : std_logic := '0';
  signal avs_byteenable  : std_logic_vector(3 downto 0) := (others => '1');
  signal avs_writedata   : std_logic_vector(31 downto 0) := (others => '0');
  signal avs_readdata    : std_logic_vector(31 downto 0);
  signal avs_waitrequest : std_logic;

  procedure av_write(
    signal chipselect_s : out std_logic;
    signal address_s    : out std_logic_vector(C_ADDR_WIDTH - 3 downto 0);
    signal write_s      : out std_logic;
    signal writedata_s  : out std_logic_vector(31 downto 0);
    signal waitreq_s    : in  std_logic;
    constant addr_w     : in  natural;
    constant data       : in  std_logic_vector(31 downto 0)
  ) is
  begin
    chipselect_s <= '1';
    address_s    <= std_logic_vector(to_unsigned(addr_w, address_s'length));
    writedata_s  <= data;
    write_s      <= '1';
    wait until rising_edge(clk);
    while waitreq_s = '1' loop
      wait until rising_edge(clk);
    end loop;
    chipselect_s <= '0';
    write_s      <= '0';
    wait until rising_edge(clk);
  end procedure;

  procedure av_read(
    signal chipselect_s : out std_logic;
    signal address_s    : out std_logic_vector(C_ADDR_WIDTH - 3 downto 0);
    signal read_s       : out std_logic;
    signal rdata_s      : in  std_logic_vector(31 downto 0);
    signal waitreq_s    : in  std_logic;
    constant addr_w     : in  natural;
    variable data       : out std_logic_vector(31 downto 0)
  ) is
  begin
    chipselect_s <= '1';
    address_s    <= std_logic_vector(to_unsigned(addr_w, address_s'length));
    read_s       <= '1';
    wait until rising_edge(clk);
    while waitreq_s = '1' loop
      wait until rising_edge(clk);
    end loop;
    data := rdata_s;
    chipselect_s <= '0';
    read_s       <= '0';
    wait until rising_edge(clk);
  end procedure;
begin
  clk <= not clk after 5 ns;

  dut : entity work.hft_trade_engine_avalon_mm
    generic map (
      G_ADDR_WIDTH => C_ADDR_WIDTH,
      G_DEPTH      => C_DEPTH,
      G_SLOT_WORDS => C_SLOT_WORDS
    )
    port map (
      clk_i            => clk,
      rst_ni           => rst_n,
      avs_chipselect_i => avs_chipselect,
      avs_address_i    => avs_address,
      avs_read_i       => avs_read,
      avs_write_i      => avs_write,
      avs_byteenable_i => avs_byteenable,
      avs_writedata_i  => avs_writedata,
      avs_readdata_o   => avs_readdata,
      avs_waitrequest_o => avs_waitrequest
    );

  stim : process
    variable rd_val : std_logic_vector(31 downto 0);
  begin
    rst_n <= '0';
    wait for 40 ns;
    wait until rising_edge(clk);
    rst_n <= '1';
    wait until rising_edge(clk);

    av_read(avs_chipselect, avs_address, avs_read, avs_readdata, avs_waitrequest, C_REG_MAGIC_W, rd_val);
    assert rd_val = x"48465431" report "MAGIC mismatch" severity failure;

    av_read(avs_chipselect, avs_address, avs_read, avs_readdata, avs_waitrequest, C_REG_VERSION_W, rd_val);
    assert rd_val = x"00000001" report "VERSION mismatch" severity failure;

    for i in 0 to 2 loop
      av_write(avs_chipselect, avs_address, avs_write, avs_writedata, avs_waitrequest, f_slot_addr_w(C_TX_BASE_W, i, 0), C_TX_W0(i));
      av_write(avs_chipselect, avs_address, avs_write, avs_writedata, avs_waitrequest, f_slot_addr_w(C_TX_BASE_W, i, 1), C_TX_W1(i));
      av_write(avs_chipselect, avs_address, avs_write, avs_writedata, avs_waitrequest, f_slot_addr_w(C_TX_BASE_W, i, 2), C_TX_W2(i));
      av_write(avs_chipselect, avs_address, avs_write, avs_writedata, avs_waitrequest, f_slot_addr_w(C_TX_BASE_W, i, 3), C_TX_W3(i));
      av_write(avs_chipselect, avs_address, avs_write, avs_writedata, avs_waitrequest, C_REG_TX_HEAD_W, f_u32(i + 1));
    end loop;

    for i in 0 to 15 loop
      wait until rising_edge(clk);
    end loop;

    av_read(avs_chipselect, avs_address, avs_read, avs_readdata, avs_waitrequest, C_REG_TX_TAIL_W, rd_val);
    assert rd_val(15 downto 0) = x"0003" report "TX_TAIL mismatch" severity failure;

    av_read(avs_chipselect, avs_address, avs_read, avs_readdata, avs_waitrequest, C_REG_RX_HEAD_W, rd_val);
    assert rd_val(15 downto 0) = x"0003" report "RX_HEAD mismatch" severity failure;

    av_read(avs_chipselect, avs_address, avs_read, avs_readdata, avs_waitrequest, C_REG_STATUS_W, rd_val);
    assert rd_val(2) = '1' report "STATUS.rx_has_data should be high" severity failure;

    for i in 0 to 2 loop
      av_read(avs_chipselect, avs_address, avs_read, avs_readdata, avs_waitrequest, f_slot_addr_w(C_RX_BASE_W, i, 0), rd_val);
      assert rd_val = C_TX_W0(i) report "RX seq mismatch" severity failure;
      av_read(avs_chipselect, avs_address, avs_read, avs_readdata, avs_waitrequest, f_slot_addr_w(C_RX_BASE_W, i, 1), rd_val);
      assert rd_val = C_EXPECT_ACTION(i) report "RX action mismatch" severity failure;
      av_read(avs_chipselect, avs_address, avs_read, avs_readdata, avs_waitrequest, f_slot_addr_w(C_RX_BASE_W, i, 2), rd_val);
      assert rd_val = C_TX_W2(i) report "RX price mismatch" severity failure;
      av_read(avs_chipselect, avs_address, avs_read, avs_readdata, avs_waitrequest, f_slot_addr_w(C_RX_BASE_W, i, 3), rd_val);
      assert rd_val = C_TX_W3(i) report "RX qty mismatch" severity failure;
      av_write(avs_chipselect, avs_address, avs_write, avs_writedata, avs_waitrequest, C_REG_RX_TAIL_W, f_u32(i + 1));
    end loop;

    av_read(avs_chipselect, avs_address, avs_read, avs_readdata, avs_waitrequest, C_REG_STATUS_W, rd_val);
    assert rd_val(2) = '0' report "STATUS.rx_has_data should clear after drain" severity failure;

    report "tb_hft_trade_engine_avalon_mm PASSED" severity note;
    wait;
  end process;
end architecture tb;
