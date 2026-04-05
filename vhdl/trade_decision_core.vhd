library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity trade_decision_core is
  generic (
    G_SLOT_WORDS         : natural := 4;
    G_BUY_QTY_THRESHOLD  : natural := 2000;
    G_SELL_QTY_THRESHOLD : natural := 2000
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
  constant C_ACTION_NOOP : natural := 0;
  constant C_ACTION_BUY  : natural := 1;
  constant C_ACTION_SELL : natural := 2;

  signal rsp_valid_q : std_logic := '0';
  signal rsp_data_q  : std_logic_vector(G_SLOT_WORDS * 32 - 1 downto 0) := (others => '0');

  function f_build_response(
    cmd_frame           : std_logic_vector(G_SLOT_WORDS * 32 - 1 downto 0);
    buy_qty_threshold   : natural;
    sell_qty_threshold  : natural
  ) return std_logic_vector is
    variable rsp       : std_logic_vector(G_SLOT_WORDS * 32 - 1 downto 0) := (others => '0');
    variable side_code : natural := 0;
    variable qty_value : natural := 0;
    variable action    : natural := C_ACTION_NOOP;
  begin
    side_code := to_integer(unsigned(cmd_frame(63 downto 56)));
    qty_value := to_integer(unsigned(cmd_frame(127 downto 96)));

    if side_code = 1 and qty_value >= buy_qty_threshold then
      action := C_ACTION_BUY;
    elsif side_code = 2 and qty_value >= sell_qty_threshold then
      action := C_ACTION_SELL;
    end if;

    rsp(31 downto 0)    := cmd_frame(31 downto 0);
    rsp(63 downto 32)   := std_logic_vector(to_unsigned(action, 32));
    rsp(95 downto 64)   := cmd_frame(95 downto 64);
    rsp(127 downto 96)  := cmd_frame(127 downto 96);
    return rsp;
  end function;
begin
  cmd_ready_o <= '1' when rsp_valid_q = '0' or rsp_ready_i = '1' else '0';

  rsp_valid_o <= rsp_valid_q;
  rsp_data_o  <= rsp_data_q;

  p_main : process(clk_i)
  begin
    if rising_edge(clk_i) then
      if rst_ni = '0' then
        rsp_valid_q <= '0';
        rsp_data_q  <= (others => '0');
      else
        if rsp_valid_q = '1' and rsp_ready_i = '1' then
          rsp_valid_q <= '0';
        end if;

        if cmd_valid_i = '1' and cmd_ready_o = '1' then
          rsp_data_q <= f_build_response(
            cmd_data_i,
            G_BUY_QTY_THRESHOLD,
            G_SELL_QTY_THRESHOLD
          );
          rsp_valid_q <= '1';
        end if;
      end if;
    end if;
  end process;
end architecture;
