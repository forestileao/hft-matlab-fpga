library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity strategy is
  port (
    best_bid_px  : in  std_logic_vector(31 downto 0);
    best_bid_qty : in  std_logic_vector(31 downto 0);
    best_ask_px  : in  std_logic_vector(31 downto 0);
    best_ask_qty : in  std_logic_vector(31 downto 0);
    spread_1e4   : in  std_logic_vector(31 downto 0);
    imbalance    : in  std_logic_vector(31 downto 0);
    action       : out std_logic_vector(31 downto 0)
  );
end entity;

architecture rtl of strategy is
  constant C_ACTION_NOOP : std_logic_vector(31 downto 0) := x"00000000";
  constant C_ACTION_BUY  : std_logic_vector(31 downto 0) := x"00000001";
  constant C_ACTION_SELL : std_logic_vector(31 downto 0) := x"00000002";
begin
  p_comb : process(all)
  begin
    action <= C_ACTION_NOOP;

    if unsigned(best_bid_qty) = 0 or unsigned(best_ask_qty) = 0 then
      action <= C_ACTION_NOOP;
    elsif unsigned(best_ask_px) <= unsigned(best_bid_px) then
      action <= C_ACTION_NOOP;
    elsif unsigned(spread_1e4) > to_unsigned(25000, 32) then
      action <= C_ACTION_NOOP;
    elsif signed(imbalance) >= to_signed(500, 32) then
      action <= C_ACTION_BUY;
    elsif signed(imbalance) <= to_signed(-500, 32) then
      action <= C_ACTION_SELL;
    end if;
  end process;
end architecture rtl;
