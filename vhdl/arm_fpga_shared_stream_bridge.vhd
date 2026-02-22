library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity arm_fpga_shared_stream_bridge is
  generic (
    G_ADDR_WIDTH : natural := 12; -- byte address width
    G_DEPTH      : natural := 64;
    G_SLOT_WORDS : natural := 4   -- 4 words = 128-bit frame
  );
  port (
    clk_i     : in  std_logic;
    rst_ni    : in  std_logic;

    -- Simple MMIO slave (32-bit data, byte-addressed)
    mm_addr_i  : in  std_logic_vector(G_ADDR_WIDTH - 1 downto 0);
    mm_wr_i    : in  std_logic;
    mm_rd_i    : in  std_logic;
    mm_wdata_i : in  std_logic_vector(31 downto 0);
    mm_rdata_o : out std_logic_vector(31 downto 0);
    mm_ready_o : out std_logic;

    -- ARM -> FPGA stream output
    cmd_valid_o : out std_logic;
    cmd_data_o  : out std_logic_vector(G_SLOT_WORDS * 32 - 1 downto 0);
    cmd_ready_i : in  std_logic;

    -- FPGA -> ARM stream input
    rsp_valid_i : in  std_logic;
    rsp_data_i  : in  std_logic_vector(G_SLOT_WORDS * 32 - 1 downto 0);
    rsp_ready_o : out std_logic
  );
end entity;

architecture rtl of arm_fpga_shared_stream_bridge is
  constant C_MAGIC   : std_logic_vector(31 downto 0) := x"48465431"; -- "HFT1"
  constant C_VERSION : std_logic_vector(31 downto 0) := x"00000001";

  -- Register map in word addresses (byte_offset / 4)
  constant C_REG_MAGIC_W      : natural := 16#000# / 4;
  constant C_REG_VERSION_W    : natural := 16#004# / 4;
  constant C_REG_CTRL_W       : natural := 16#008# / 4;
  constant C_REG_STATUS_W     : natural := 16#00C# / 4;
  constant C_REG_TX_HEAD_W    : natural := 16#010# / 4; -- ARM writes
  constant C_REG_TX_TAIL_W    : natural := 16#014# / 4; -- FPGA writes
  constant C_REG_RX_HEAD_W    : natural := 16#018# / 4; -- FPGA writes
  constant C_REG_RX_TAIL_W    : natural := 16#01C# / 4; -- ARM writes
  constant C_REG_TX_DEPTH_W   : natural := 16#020# / 4;
  constant C_REG_RX_DEPTH_W   : natural := 16#024# / 4;
  constant C_REG_SLOT_WORDS_W : natural := 16#028# / 4;

  constant C_TX_BASE_W : natural := 16#100# / 4;
  constant C_RX_BASE_W : natural := C_TX_BASE_W + (G_DEPTH * G_SLOT_WORDS);

  subtype t_slot is std_logic_vector(G_SLOT_WORDS * 32 - 1 downto 0);
  type t_ram is array (0 to G_DEPTH - 1) of t_slot;

  signal tx_ram_q : t_ram := (others => (others => '0'));
  signal rx_ram_q : t_ram := (others => (others => '0'));

  signal tx_head_q : unsigned(15 downto 0) := (others => '0');
  signal tx_tail_q : unsigned(15 downto 0) := (others => '0');
  signal rx_head_q : unsigned(15 downto 0) := (others => '0');
  signal rx_tail_q : unsigned(15 downto 0) := (others => '0');

  signal mm_rdata_q : std_logic_vector(31 downto 0) := (others => '0');
  signal mm_ready_q : std_logic := '0';

  signal tx_empty_s : std_logic;
  signal tx_full_s  : std_logic;
  signal rx_empty_s : std_logic;
  signal rx_full_s  : std_logic;

  function f_inc_wrap(v : unsigned) return unsigned is
    variable r : unsigned(v'range);
  begin
    if to_integer(v) = (G_DEPTH - 1) then
      r := (others => '0');
    else
      r := v + 1;
    end if;
    return r;
  end function;

  function f_slot_word_get(slot : t_slot; lane : natural) return std_logic_vector is
    variable v : std_logic_vector(31 downto 0);
    variable lsb : natural := lane * 32;
  begin
    v := slot(lsb + 31 downto lsb);
    return v;
  end function;

  function f_slot_word_set(
    slot  : t_slot;
    lane  : natural;
    value : std_logic_vector(31 downto 0)
  ) return t_slot is
    variable v : t_slot := slot;
    variable lsb : natural := lane * 32;
  begin
    v(lsb + 31 downto lsb) := value;
    return v;
  end function;

begin
  tx_empty_s <= '1' when tx_head_q = tx_tail_q else '0';
  tx_full_s  <= '1' when f_inc_wrap(tx_head_q) = tx_tail_q else '0';
  rx_empty_s <= '1' when rx_head_q = rx_tail_q else '0';
  rx_full_s  <= '1' when f_inc_wrap(rx_head_q) = rx_tail_q else '0';

  cmd_valid_o <= not tx_empty_s;
  cmd_data_o  <= tx_ram_q(to_integer(tx_tail_q));
  rsp_ready_o <= not rx_full_s;

  mm_rdata_o <= mm_rdata_q;
  mm_ready_o <= mm_ready_q;

  p_main : process(clk_i)
    variable waddr    : natural;
    variable rel      : natural;
    variable slot_idx : natural;
    variable lane_idx : natural;
    variable status_v : std_logic_vector(31 downto 0);
  begin
    if rising_edge(clk_i) then
      if rst_ni = '0' then
        tx_head_q  <= (others => '0');
        tx_tail_q  <= (others => '0');
        rx_head_q  <= (others => '0');
        rx_tail_q  <= (others => '0');
        mm_rdata_q <= (others => '0');
        mm_ready_q <= '0';
      else
        mm_ready_q <= '0';
        mm_rdata_q <= (others => '0');

        -- Consume ARM->FPGA queue into stream.
        if cmd_valid_o = '1' and cmd_ready_i = '1' then
          tx_tail_q <= f_inc_wrap(tx_tail_q);
        end if;

        -- Capture FPGA->ARM stream into queue.
        if rsp_valid_i = '1' and rx_full_s = '0' then
          rx_ram_q(to_integer(rx_head_q)) <= rsp_data_i;
          rx_head_q <= f_inc_wrap(rx_head_q);
        end if;

        if mm_wr_i = '1' then
          mm_ready_q <= '1';
          waddr := to_integer(unsigned(mm_addr_i(G_ADDR_WIDTH - 1 downto 2)));

          if waddr = C_REG_CTRL_W then
            -- bit0: soft reset of queue pointers
            if mm_wdata_i(0) = '1' then
              tx_head_q <= (others => '0');
              tx_tail_q <= (others => '0');
              rx_head_q <= (others => '0');
              rx_tail_q <= (others => '0');
            end if;
          elsif waddr = C_REG_TX_HEAD_W then
            tx_head_q <= to_unsigned(
              to_integer(unsigned(mm_wdata_i(15 downto 0))) mod G_DEPTH,
              tx_head_q'length
            );
          elsif waddr = C_REG_RX_TAIL_W then
            rx_tail_q <= to_unsigned(
              to_integer(unsigned(mm_wdata_i(15 downto 0))) mod G_DEPTH,
              rx_tail_q'length
            );
          elsif waddr >= C_TX_BASE_W and waddr < (C_TX_BASE_W + (G_DEPTH * G_SLOT_WORDS)) then
            rel := waddr - C_TX_BASE_W;
            slot_idx := rel / G_SLOT_WORDS;
            lane_idx := rel mod G_SLOT_WORDS;
            tx_ram_q(slot_idx) <= f_slot_word_set(tx_ram_q(slot_idx), lane_idx, mm_wdata_i);
          elsif waddr >= C_RX_BASE_W and waddr < (C_RX_BASE_W + (G_DEPTH * G_SLOT_WORDS)) then
            -- Optional debug write path for simulation/bring-up.
            rel := waddr - C_RX_BASE_W;
            slot_idx := rel / G_SLOT_WORDS;
            lane_idx := rel mod G_SLOT_WORDS;
            rx_ram_q(slot_idx) <= f_slot_word_set(rx_ram_q(slot_idx), lane_idx, mm_wdata_i);
          end if;

        elsif mm_rd_i = '1' then
          mm_ready_q <= '1';
          waddr := to_integer(unsigned(mm_addr_i(G_ADDR_WIDTH - 1 downto 2)));

          if waddr = C_REG_MAGIC_W then
            mm_rdata_q <= C_MAGIC;
          elsif waddr = C_REG_VERSION_W then
            mm_rdata_q <= C_VERSION;
          elsif waddr = C_REG_STATUS_W then
            status_v := (others => '0');
            -- bit0 can_send, bit1 tx_full, bit2 rx_has_data, bit3 rx_full
            status_v(0) := not tx_full_s;
            status_v(1) := tx_full_s;
            status_v(2) := not rx_empty_s;
            status_v(3) := rx_full_s;
            mm_rdata_q <= status_v;
          elsif waddr = C_REG_TX_HEAD_W then
            mm_rdata_q <= std_logic_vector(resize(tx_head_q, 32));
          elsif waddr = C_REG_TX_TAIL_W then
            mm_rdata_q <= std_logic_vector(resize(tx_tail_q, 32));
          elsif waddr = C_REG_RX_HEAD_W then
            mm_rdata_q <= std_logic_vector(resize(rx_head_q, 32));
          elsif waddr = C_REG_RX_TAIL_W then
            mm_rdata_q <= std_logic_vector(resize(rx_tail_q, 32));
          elsif waddr = C_REG_TX_DEPTH_W then
            mm_rdata_q <= std_logic_vector(to_unsigned(G_DEPTH, 32));
          elsif waddr = C_REG_RX_DEPTH_W then
            mm_rdata_q <= std_logic_vector(to_unsigned(G_DEPTH, 32));
          elsif waddr = C_REG_SLOT_WORDS_W then
            mm_rdata_q <= std_logic_vector(to_unsigned(G_SLOT_WORDS, 32));
          elsif waddr >= C_TX_BASE_W and waddr < (C_TX_BASE_W + (G_DEPTH * G_SLOT_WORDS)) then
            rel := waddr - C_TX_BASE_W;
            slot_idx := rel / G_SLOT_WORDS;
            lane_idx := rel mod G_SLOT_WORDS;
            mm_rdata_q <= f_slot_word_get(tx_ram_q(slot_idx), lane_idx);
          elsif waddr >= C_RX_BASE_W and waddr < (C_RX_BASE_W + (G_DEPTH * G_SLOT_WORDS)) then
            rel := waddr - C_RX_BASE_W;
            slot_idx := rel / G_SLOT_WORDS;
            lane_idx := rel mod G_SLOT_WORDS;
            mm_rdata_q <= f_slot_word_get(rx_ram_q(slot_idx), lane_idx);
          end if;
        end if;
      end if;
    end if;
  end process;

end architecture;

