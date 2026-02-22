library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_arm_fpga_shared_stream_bridge_fast is
end entity;

architecture tb of tb_arm_fpga_shared_stream_bridge_fast is
  constant C_ADDR_WIDTH : natural := 12;
  constant C_DEPTH      : natural := 8;
  constant C_SLOT_WORDS : natural := 4;

  constant C_REG_MAGIC    : natural := 16#000#;
  constant C_REG_VERSION  : natural := 16#004#;
  constant C_REG_STATUS   : natural := 16#00C#;
  constant C_REG_TX_HEAD  : natural := 16#010#;
  constant C_REG_TX_TAIL  : natural := 16#014#;
  constant C_REG_RX_HEAD  : natural := 16#018#;
  constant C_REG_RX_TAIL  : natural := 16#01C#;
  constant C_REG_TX_DEPTH : natural := 16#020#;
  constant C_REG_RX_DEPTH : natural := 16#024#;

  constant C_TX_BASE : natural := 16#100#;
  constant C_RX_BASE : natural := C_TX_BASE + (C_DEPTH * C_SLOT_WORDS * 4);

  constant C_TX_BURST : natural := 12;
  constant C_RX_BURST : natural := 10;

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

  function f_next(v : natural) return natural is
  begin
    if v = C_DEPTH - 1 then
      return 0;
    end if;
    return v + 1;
  end function;

  function f_slot_addr(base : natural; slot : natural; lane : natural) return natural is
  begin
    return base + slot * C_SLOT_WORDS * 4 + lane * 4;
  end function;

  constant C_TX_W1 : t_u32_array(0 to C_TX_BURST - 1) := (
    f_pack_symbol_side("AAP", 1), -- buy
    f_pack_symbol_side("MSF", 2), -- sell
    f_pack_symbol_side("NVD", 1),
    f_pack_symbol_side("GOO", 2),
    f_pack_symbol_side("TSL", 1),
    f_pack_symbol_side("AAP", 2),
    f_pack_symbol_side("MSF", 1),
    f_pack_symbol_side("NVD", 2),
    f_pack_symbol_side("GOO", 1),
    f_pack_symbol_side("TSL", 2),
    f_pack_symbol_side("AAP", 1),
    f_pack_symbol_side("MSF", 2)
  );

  constant C_TX_W2 : t_u32_array(0 to C_TX_BURST - 1) := (
    x"001C3A90", -- 185.0000 * 1e4
    x"003F52F0", -- 415.0000 * 1e4
    x"008583B0", -- 875.0000 * 1e4
    x"0019F0A0", -- 170.0000 * 1e4
    x"001AB3F0", -- 175.0000 * 1e4
    x"001C3F72", -- 185.1250 * 1e4
    x"003F4E0E", -- 414.8750 * 1e4
    x"00857028", -- 874.5000 * 1e4
    x"0019FA64", -- 170.2500 * 1e4
    x"001AC296", -- 175.3750 * 1e4
    x"001C3A90",
    x"003F52F0"
  );

  constant C_TX_W3 : t_u32_array(0 to C_TX_BURST - 1) := (
    x"000003E8", -- 1000
    x"000005DC", -- 1500
    x"000007D0", -- 2000
    x"000009C4", -- 2500
    x"00000BB8", -- 3000
    x"0000044C", -- 1100
    x"00000640", -- 1600
    x"00000834", -- 2100
    x"00000A28", -- 2600
    x"00000C1C", -- 3100
    x"000004B0", -- 1200
    x"000006A4"  -- 1700
  );

  function f_tx_word0(idx : natural) return std_logic_vector is
  begin
    return f_u32(idx + 1);
  end function;

  function f_tx_word1(idx : natural) return std_logic_vector is
  begin
    return C_TX_W1(idx);
  end function;

  function f_tx_word2(idx : natural) return std_logic_vector is
  begin
    return C_TX_W2(idx);
  end function;

  function f_tx_word3(idx : natural) return std_logic_vector is
  begin
    return C_TX_W3(idx);
  end function;

  function f_rsp_word0(idx : natural) return std_logic_vector is
  begin
    return f_u32(1000 + idx);
  end function;

  function f_rsp_word1(idx : natural) return std_logic_vector is
  begin
    return C_TX_W1(idx mod C_TX_BURST);
  end function;

  function f_rsp_word2(idx : natural) return std_logic_vector is
  begin
    return std_logic_vector(to_unsigned(16#10000000# + idx * 17, 32));
  end function;

  function f_rsp_word3(idx : natural) return std_logic_vector is
  begin
    return f_u32(5000 + idx * 25);
  end function;

  function f_rsp_frame(idx : natural) return std_logic_vector is
    variable frame : std_logic_vector(127 downto 0) := (others => '0');
  begin
    frame(31 downto 0)    := f_rsp_word0(idx);
    frame(63 downto 32)   := f_rsp_word1(idx);
    frame(95 downto 64)   := f_rsp_word2(idx);
    frame(127 downto 96)  := f_rsp_word3(idx);
    return frame;
  end function;

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
      clk_i       => clk,
      rst_ni      => rst_n,
      mm_addr_i   => mm_addr,
      mm_wr_i     => mm_wr,
      mm_rd_i     => mm_rd,
      mm_wdata_i  => mm_wdata,
      mm_rdata_o  => mm_rdata,
      mm_ready_o  => mm_ready,
      cmd_valid_o => cmd_valid,
      cmd_data_o  => cmd_data,
      cmd_ready_i => cmd_ready,
      rsp_valid_i => rsp_valid,
      rsp_data_i  => rsp_data,
      rsp_ready_o => rsp_ready
    );

  stim : process
    variable rd_val         : std_logic_vector(31 downto 0);
    variable arm_head       : natural := 0;
    variable tx_consume_idx : natural := 0;
    variable rx_tail_sw     : natural := 0;
    variable rx_expect_idx  : natural := 0;
  begin
    -- Reset.
    rst_n <= '0';
    wait for 40 ns;
    wait until rising_edge(clk);
    rst_n <= '1';
    wait until rising_edge(clk);

    -- Basic register sanity.
    mm_read(mm_addr, mm_rd, mm_rdata, mm_ready, C_REG_MAGIC, rd_val);
    assert rd_val = x"48465431" report "MAGIC mismatch" severity failure;
    mm_read(mm_addr, mm_rd, mm_rdata, mm_ready, C_REG_VERSION, rd_val);
    assert rd_val = x"00000001" report "VERSION mismatch" severity failure;
    mm_read(mm_addr, mm_rd, mm_rdata, mm_ready, C_REG_TX_DEPTH, rd_val);
    assert rd_val = f_u32(C_DEPTH) report "TX depth mismatch" severity failure;
    mm_read(mm_addr, mm_rd, mm_rdata, mm_ready, C_REG_RX_DEPTH, rd_val);
    assert rd_val = f_u32(C_DEPTH) report "RX depth mismatch" severity failure;

    -- TX phase 1: publish depth-1 frames while FPGA is stalled.
    cmd_ready <= '0';
    for i in 0 to C_DEPTH - 2 loop
      mm_write(mm_addr, mm_wr, mm_wdata, mm_ready, f_slot_addr(C_TX_BASE, arm_head, 0), f_tx_word0(i));
      mm_write(mm_addr, mm_wr, mm_wdata, mm_ready, f_slot_addr(C_TX_BASE, arm_head, 1), f_tx_word1(i));
      mm_write(mm_addr, mm_wr, mm_wdata, mm_ready, f_slot_addr(C_TX_BASE, arm_head, 2), f_tx_word2(i));
      mm_write(mm_addr, mm_wr, mm_wdata, mm_ready, f_slot_addr(C_TX_BASE, arm_head, 3), f_tx_word3(i));
      arm_head := f_next(arm_head);
      mm_write(mm_addr, mm_wr, mm_wdata, mm_ready, C_REG_TX_HEAD, f_u32(arm_head));
    end loop;

    mm_read(mm_addr, mm_rd, mm_rdata, mm_ready, C_REG_STATUS, rd_val);
    assert rd_val(0) = '0' report "STATUS.can_send should be 0 when TX full" severity failure;
    assert rd_val(1) = '1' report "STATUS.tx_full should be 1 when TX full" severity failure;

    -- Consume only a few frames first.
    cmd_ready <= '1';
    for i in 0 to 3 loop
      wait until rising_edge(clk);
      assert cmd_valid = '1' report "cmd_valid expected during TX consume burst" severity failure;
      assert cmd_data(31 downto 0)    = f_tx_word0(tx_consume_idx) report "TX w0 mismatch (phase1)" severity failure;
      assert cmd_data(63 downto 32)   = f_tx_word1(tx_consume_idx) report "TX w1 mismatch (phase1)" severity failure;
      assert cmd_data(95 downto 64)   = f_tx_word2(tx_consume_idx) report "TX w2 mismatch (phase1)" severity failure;
      assert cmd_data(127 downto 96)  = f_tx_word3(tx_consume_idx) report "TX w3 mismatch (phase1)" severity failure;
      tx_consume_idx := tx_consume_idx + 1;
    end loop;

    -- Publish remaining frames (forces pointer wrap-around).
    cmd_ready <= '0';
    wait until rising_edge(clk);
    for i in C_DEPTH - 1 to C_TX_BURST - 1 loop
      -- Respect queue capacity while publishing. If full, consume one frame.
      mm_read(mm_addr, mm_rd, mm_rdata, mm_ready, C_REG_STATUS, rd_val);
      while rd_val(0) = '0' loop
        cmd_ready <= '1';
        wait until rising_edge(clk);
        assert cmd_valid = '1' report "cmd_valid expected while draining full TX queue" severity failure;
        assert cmd_data(31 downto 0)    = f_tx_word0(tx_consume_idx) report "TX w0 mismatch (drain)" severity failure;
        assert cmd_data(63 downto 32)   = f_tx_word1(tx_consume_idx) report "TX w1 mismatch (drain)" severity failure;
        assert cmd_data(95 downto 64)   = f_tx_word2(tx_consume_idx) report "TX w2 mismatch (drain)" severity failure;
        assert cmd_data(127 downto 96)  = f_tx_word3(tx_consume_idx) report "TX w3 mismatch (drain)" severity failure;
        tx_consume_idx := tx_consume_idx + 1;
        cmd_ready <= '0';
        wait until rising_edge(clk);
        mm_read(mm_addr, mm_rd, mm_rdata, mm_ready, C_REG_STATUS, rd_val);
      end loop;

      mm_write(mm_addr, mm_wr, mm_wdata, mm_ready, f_slot_addr(C_TX_BASE, arm_head, 0), f_tx_word0(i));
      mm_write(mm_addr, mm_wr, mm_wdata, mm_ready, f_slot_addr(C_TX_BASE, arm_head, 1), f_tx_word1(i));
      mm_write(mm_addr, mm_wr, mm_wdata, mm_ready, f_slot_addr(C_TX_BASE, arm_head, 2), f_tx_word2(i));
      mm_write(mm_addr, mm_wr, mm_wdata, mm_ready, f_slot_addr(C_TX_BASE, arm_head, 3), f_tx_word3(i));
      arm_head := f_next(arm_head);
      mm_write(mm_addr, mm_wr, mm_wdata, mm_ready, C_REG_TX_HEAD, f_u32(arm_head));
    end loop;

    -- Consume everything and verify strict order.
    cmd_ready <= '1';
    while tx_consume_idx < C_TX_BURST loop
      wait until rising_edge(clk);
      if cmd_valid = '1' then
        assert cmd_data(31 downto 0)    = f_tx_word0(tx_consume_idx) report "TX w0 mismatch (phase2)" severity failure;
        assert cmd_data(63 downto 32)   = f_tx_word1(tx_consume_idx) report "TX w1 mismatch (phase2)" severity failure;
        assert cmd_data(95 downto 64)   = f_tx_word2(tx_consume_idx) report "TX w2 mismatch (phase2)" severity failure;
        assert cmd_data(127 downto 96)  = f_tx_word3(tx_consume_idx) report "TX w3 mismatch (phase2)" severity failure;
        tx_consume_idx := tx_consume_idx + 1;
      end if;
    end loop;

    wait until rising_edge(clk);
    assert cmd_valid = '0' report "cmd_valid should deassert when TX queue is empty" severity failure;

    mm_read(mm_addr, mm_rd, mm_rdata, mm_ready, C_REG_TX_HEAD, rd_val);
    assert rd_val(15 downto 0) = std_logic_vector(to_unsigned(arm_head, 16))
      report "TX_HEAD mismatch at end of TX phase" severity failure;
    mm_read(mm_addr, mm_rd, mm_rdata, mm_ready, C_REG_TX_TAIL, rd_val);
    assert rd_val(15 downto 0) = std_logic_vector(to_unsigned(arm_head, 16))
      report "TX_TAIL mismatch at end of TX phase" severity failure;

    -- RX phase 1: fill queue to full.
    rsp_valid <= '0';
    for i in 0 to C_DEPTH - 2 loop
      assert rsp_ready = '1' report "rsp_ready should be high before RX is full" severity failure;
      rsp_data  <= f_rsp_frame(i);
      rsp_valid <= '1';
      wait until rising_edge(clk);
      rsp_valid <= '0';
      wait until rising_edge(clk);
    end loop;

    wait until rising_edge(clk);
    assert rsp_ready = '0' report "rsp_ready should go low when RX queue is full" severity failure;
    mm_read(mm_addr, mm_rd, mm_rdata, mm_ready, C_REG_STATUS, rd_val);
    assert rd_val(2) = '1' report "STATUS.rx_has_data should be 1 after RX fill" severity failure;
    assert rd_val(3) = '1' report "STATUS.rx_full should be 1 after RX fill" severity failure;

    -- Drain some responses from ARM side.
    for i in 0 to 3 loop
      mm_read(mm_addr, mm_rd, mm_rdata, mm_ready, f_slot_addr(C_RX_BASE, rx_tail_sw, 0), rd_val);
      assert rd_val = f_rsp_word0(rx_expect_idx) report "RX w0 mismatch (phase1)" severity failure;
      mm_read(mm_addr, mm_rd, mm_rdata, mm_ready, f_slot_addr(C_RX_BASE, rx_tail_sw, 1), rd_val);
      assert rd_val = f_rsp_word1(rx_expect_idx) report "RX w1 mismatch (phase1)" severity failure;
      mm_read(mm_addr, mm_rd, mm_rdata, mm_ready, f_slot_addr(C_RX_BASE, rx_tail_sw, 2), rd_val);
      assert rd_val = f_rsp_word2(rx_expect_idx) report "RX w2 mismatch (phase1)" severity failure;
      mm_read(mm_addr, mm_rd, mm_rdata, mm_ready, f_slot_addr(C_RX_BASE, rx_tail_sw, 3), rd_val);
      assert rd_val = f_rsp_word3(rx_expect_idx) report "RX w3 mismatch (phase1)" severity failure;

      rx_tail_sw := f_next(rx_tail_sw);
      mm_write(mm_addr, mm_wr, mm_wdata, mm_ready, C_REG_RX_TAIL, f_u32(rx_tail_sw));
      rx_expect_idx := rx_expect_idx + 1;
    end loop;

    wait until rising_edge(clk);
    assert rsp_ready = '1' report "rsp_ready should return high after RX drain" severity failure;

    -- Push remaining responses (also wraps RX head).
    for i in C_DEPTH - 1 to C_RX_BURST - 1 loop
      while rsp_ready = '0' loop
        wait until rising_edge(clk);
      end loop;
      rsp_data  <= f_rsp_frame(i);
      rsp_valid <= '1';
      wait until rising_edge(clk);
      rsp_valid <= '0';
      wait until rising_edge(clk);
    end loop;

    -- Drain all remaining responses and verify.
    while rx_expect_idx < C_RX_BURST loop
      mm_read(mm_addr, mm_rd, mm_rdata, mm_ready, f_slot_addr(C_RX_BASE, rx_tail_sw, 0), rd_val);
      assert rd_val = f_rsp_word0(rx_expect_idx) report "RX w0 mismatch (phase2)" severity failure;
      mm_read(mm_addr, mm_rd, mm_rdata, mm_ready, f_slot_addr(C_RX_BASE, rx_tail_sw, 1), rd_val);
      assert rd_val = f_rsp_word1(rx_expect_idx) report "RX w1 mismatch (phase2)" severity failure;
      mm_read(mm_addr, mm_rd, mm_rdata, mm_ready, f_slot_addr(C_RX_BASE, rx_tail_sw, 2), rd_val);
      assert rd_val = f_rsp_word2(rx_expect_idx) report "RX w2 mismatch (phase2)" severity failure;
      mm_read(mm_addr, mm_rd, mm_rdata, mm_ready, f_slot_addr(C_RX_BASE, rx_tail_sw, 3), rd_val);
      assert rd_val = f_rsp_word3(rx_expect_idx) report "RX w3 mismatch (phase2)" severity failure;

      rx_tail_sw := f_next(rx_tail_sw);
      mm_write(mm_addr, mm_wr, mm_wdata, mm_ready, C_REG_RX_TAIL, f_u32(rx_tail_sw));
      rx_expect_idx := rx_expect_idx + 1;
    end loop;

    mm_read(mm_addr, mm_rd, mm_rdata, mm_ready, C_REG_RX_HEAD, rd_val);
    assert rd_val(15 downto 0) = std_logic_vector(to_unsigned(C_RX_BURST mod C_DEPTH, 16))
      report "RX_HEAD mismatch at end of RX phase" severity failure;
    mm_read(mm_addr, mm_rd, mm_rdata, mm_ready, C_REG_STATUS, rd_val);
    assert rd_val(2) = '0' report "STATUS.rx_has_data should be 0 after final drain" severity failure;
    assert rd_val(3) = '0' report "STATUS.rx_full should be 0 after final drain" severity failure;

    report "tb_arm_fpga_shared_stream_bridge_fast PASSED" severity note;
    wait;
  end process;

end architecture;
