library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_arm_fpga_shared_stream_bridge is
end entity;

architecture sim of tb_arm_fpga_shared_stream_bridge is
  constant C_ADDR_WIDTH : natural := 13;
  constant C_DEPTH      : natural := 4;
  constant C_SLOT_WORDS : natural := 8;
  constant C_TX_BASE    : natural := 16#100#;
  constant C_RX_BASE    : natural := C_TX_BASE + (C_DEPTH * C_SLOT_WORDS * 4);

  signal clk     : std_logic := '0';
  signal rst_n   : std_logic := '0';

  signal mm_addr  : std_logic_vector(C_ADDR_WIDTH - 1 downto 0) := (others => '0');
  signal mm_wr    : std_logic := '0';
  signal mm_rd    : std_logic := '0';
  signal mm_wdata : std_logic_vector(31 downto 0) := (others => '0');
  signal mm_rdata : std_logic_vector(31 downto 0);
  signal mm_ready : std_logic;

  signal cmd_valid : std_logic;
  signal cmd_data  : std_logic_vector(C_SLOT_WORDS * 32 - 1 downto 0);
  signal cmd_ready : std_logic := '0';

  signal rsp_valid : std_logic := '0';
  signal rsp_data  : std_logic_vector(C_SLOT_WORDS * 32 - 1 downto 0) := (others => '0');
  signal rsp_ready : std_logic;

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

  dut : entity work.arm_fpga_shared_stream_bridge
    generic map (
      G_ADDR_WIDTH => C_ADDR_WIDTH,
      G_DEPTH      => C_DEPTH,
      G_SLOT_WORDS => C_SLOT_WORDS
    )
    port map (
      clk_i      => clk,
      rst_ni     => rst_n,
      mm_addr_i  => mm_addr,
      mm_wr_i    => mm_wr,
      mm_rd_i    => mm_rd,
      mm_wdata_i => mm_wdata,
      mm_rdata_o => mm_rdata,
      mm_ready_o => mm_ready,
      cmd_valid_o => cmd_valid,
      cmd_data_o  => cmd_data,
      cmd_ready_i => cmd_ready,
      rsp_valid_i => rsp_valid,
      rsp_data_i  => rsp_data,
      rsp_ready_o => rsp_ready
    );

  stim : process
    variable rd_val : std_logic_vector(31 downto 0);
  begin
    -- reset
    rst_n <= '0';
    wait for 40 ns;
    wait until rising_edge(clk);
    rst_n <= '1';
    wait until rising_edge(clk);

    -- Read magic/version
    mm_read(mm_addr, mm_rd, mm_rdata, mm_ready, 16#000#, rd_val);
    assert rd_val = x"48465431" report "MAGIC mismatch" severity failure;

    mm_read(mm_addr, mm_rd, mm_rdata, mm_ready, 16#004#, rd_val);
    assert rd_val = x"00000001" report "VERSION mismatch" severity failure;

    -- Prepare one TX frame in slot 0
    mm_write(mm_addr, mm_wr, mm_wdata, mm_ready, C_TX_BASE + 16#000#, x"0000002A");
    mm_write(mm_addr, mm_wr, mm_wdata, mm_ready, C_TX_BASE + 16#004#, x"00000000");
    mm_write(mm_addr, mm_wr, mm_wdata, mm_ready, C_TX_BASE + 16#008#, x"001C3A90");
    mm_write(mm_addr, mm_wr, mm_wdata, mm_ready, C_TX_BASE + 16#00C#, x"000009C4");
    mm_write(mm_addr, mm_wr, mm_wdata, mm_ready, C_TX_BASE + 16#010#, x"00000001");
    mm_write(mm_addr, mm_wr, mm_wdata, mm_ready, C_TX_BASE + 16#014#, x"00000001");
    mm_write(mm_addr, mm_wr, mm_wdata, mm_ready, C_TX_BASE + 16#018#, x"00000000");
    mm_write(mm_addr, mm_wr, mm_wdata, mm_ready, C_TX_BASE + 16#01C#, x"00000000");

    cmd_ready <= '0';
    mm_write(mm_addr, mm_wr, mm_wdata, mm_ready, 16#010#, x"00000001"); -- TX_HEAD=1
    wait until rising_edge(clk);

    assert cmd_valid = '1' report "cmd_valid should assert after TX_HEAD publish" severity failure;
    assert cmd_data(31 downto 0)    = x"0000002A" report "cmd_data word0 mismatch" severity failure;
    assert cmd_data(63 downto 32)   = x"00000000" report "cmd_data word1 mismatch" severity failure;
    assert cmd_data(95 downto 64)   = x"001C3A90" report "cmd_data word2 mismatch" severity failure;
    assert cmd_data(127 downto 96)  = x"000009C4" report "cmd_data word3 mismatch" severity failure;
    assert cmd_data(159 downto 128) = x"00000001" report "cmd_data word4 mismatch" severity failure;
    assert cmd_data(191 downto 160) = x"00000001" report "cmd_data word5 mismatch" severity failure;
    assert cmd_data(223 downto 192) = x"00000000" report "cmd_data word6 mismatch" severity failure;
    assert cmd_data(255 downto 224) = x"00000000" report "cmd_data word7 mismatch" severity failure;

    -- consume command in FPGA stream
    cmd_ready <= '1';
    wait until rising_edge(clk);
    wait until rising_edge(clk);
    assert cmd_valid = '0' report "cmd_valid should deassert after consume" severity failure;

    -- Push one response frame from FPGA stream
    rsp_data(31 downto 0)    <= x"0000000A";
    rsp_data(63 downto 32)   <= x"00000001";
    rsp_data(95 downto 64)   <= x"001C3A90";
    rsp_data(127 downto 96)  <= x"000009C4";
    rsp_data(159 downto 128) <= x"001C4260";
    rsp_data(191 downto 160) <= x"000004B0";
    rsp_data(223 downto 192) <= x"000007D0";
    rsp_data(255 downto 224) <= x"00000514";
    rsp_valid <= '1';
    wait until rising_edge(clk);
    rsp_valid <= '0';
    wait until rising_edge(clk);

    mm_read(mm_addr, mm_rd, mm_rdata, mm_ready, 16#018#, rd_val); -- RX_HEAD
    assert rd_val(15 downto 0) = x"0001" report "RX_HEAD should be 1" severity failure;

    mm_read(mm_addr, mm_rd, mm_rdata, mm_ready, C_RX_BASE + 16#000#, rd_val);
    assert rd_val = x"0000000A" report "RX slot word0 mismatch" severity failure;
    mm_read(mm_addr, mm_rd, mm_rdata, mm_ready, C_RX_BASE + 16#004#, rd_val);
    assert rd_val = x"00000001" report "RX slot word1 mismatch" severity failure;
    mm_read(mm_addr, mm_rd, mm_rdata, mm_ready, C_RX_BASE + 16#008#, rd_val);
    assert rd_val = x"001C3A90" report "RX slot word2 mismatch" severity failure;
    mm_read(mm_addr, mm_rd, mm_rdata, mm_ready, C_RX_BASE + 16#00C#, rd_val);
    assert rd_val = x"000009C4" report "RX slot word3 mismatch" severity failure;
    mm_read(mm_addr, mm_rd, mm_rdata, mm_ready, C_RX_BASE + 16#010#, rd_val);
    assert rd_val = x"001C4260" report "RX slot word4 mismatch" severity failure;
    mm_read(mm_addr, mm_rd, mm_rdata, mm_ready, C_RX_BASE + 16#014#, rd_val);
    assert rd_val = x"000004B0" report "RX slot word5 mismatch" severity failure;
    mm_read(mm_addr, mm_rd, mm_rdata, mm_ready, C_RX_BASE + 16#018#, rd_val);
    assert rd_val = x"000007D0" report "RX slot word6 mismatch" severity failure;
    mm_read(mm_addr, mm_rd, mm_rdata, mm_ready, C_RX_BASE + 16#01C#, rd_val);
    assert rd_val = x"00000514" report "RX slot word7 mismatch" severity failure;

    -- ARM ack receive
    mm_write(mm_addr, mm_wr, mm_wdata, mm_ready, 16#01C#, x"00000001"); -- RX_TAIL=1
    mm_read(mm_addr, mm_rd, mm_rdata, mm_ready, 16#00C#, rd_val); -- STATUS
    assert rd_val(2) = '0' report "STATUS.rx_has_data should be 0 after ack" severity failure;

    report "tb_arm_fpga_shared_stream_bridge PASSED" severity note;
    wait;
  end process;

end architecture sim;
