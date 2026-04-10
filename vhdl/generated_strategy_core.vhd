library ieee;
use ieee.std_logic_1164.all;

entity generated_strategy_core is
  generic (
    G_SLOT_WORDS          : natural := 8;
    G_IMBALANCE_THRESHOLD : natural := 500;
    G_MAX_SPREAD_1E4      : natural := 25000
  );
  port (
    clk_i : in std_logic;
    rst_ni : in std_logic;

    snapshot_valid_i : in std_logic;
    snapshot_seq_i   : in std_logic_vector(31 downto 0);
    best_bid_px_i    : in std_logic_vector(31 downto 0);
    best_bid_qty_i   : in std_logic_vector(31 downto 0);
    best_ask_px_i    : in std_logic_vector(31 downto 0);
    best_ask_qty_i   : in std_logic_vector(31 downto 0);
    spread_1e4_i     : in std_logic_vector(31 downto 0);
    imbalance_i      : in std_logic_vector(31 downto 0);
    snapshot_ready_o : out std_logic;

    rsp_valid_o : out std_logic;
    rsp_data_o  : out std_logic_vector(G_SLOT_WORDS * 32 - 1 downto 0);
    rsp_ready_i : in  std_logic
  );
end entity;

architecture rtl of generated_strategy_core is
  signal snapshot_ready_s : std_logic;
  signal rsp_valid_q : std_logic := '0';
  signal rsp_data_q  : std_logic_vector(G_SLOT_WORDS * 32 - 1 downto 0) := (others => '0');
  signal action_s    : std_logic_vector(31 downto 0);

  function f_build_response(
    seq_v        : std_logic_vector(31 downto 0);
    action_v     : std_logic_vector(31 downto 0);
    best_bid_px  : std_logic_vector(31 downto 0);
    best_bid_qty : std_logic_vector(31 downto 0);
    best_ask_px  : std_logic_vector(31 downto 0);
    best_ask_qty : std_logic_vector(31 downto 0);
    spread_1e4   : std_logic_vector(31 downto 0);
    imbalance    : std_logic_vector(31 downto 0)
  ) return std_logic_vector is
    variable rsp : std_logic_vector(G_SLOT_WORDS * 32 - 1 downto 0) := (others => '0');
  begin
    rsp(31 downto 0) := seq_v;
    rsp(63 downto 32) := action_v;
    rsp(95 downto 64) := best_bid_px;
    rsp(127 downto 96) := best_bid_qty;
    rsp(159 downto 128) := best_ask_px;
    rsp(191 downto 160) := best_ask_qty;
    rsp(223 downto 192) := spread_1e4;
    rsp(255 downto 224) := imbalance;
    return rsp;
  end function;
begin
  -- The generated MATLAB block is combinational; this wrapper keeps the
  -- existing snapshot/rsp handshake contract intact.
  u_generated_strategy : entity work.strategy
    port map (
      best_bid_px  => best_bid_px_i,
      best_bid_qty => best_bid_qty_i,
      best_ask_px  => best_ask_px_i,
      best_ask_qty => best_ask_qty_i,
      spread_1e4   => spread_1e4_i,
      imbalance    => imbalance_i,
      action       => action_s
    );

  snapshot_ready_s <= '1' when rsp_valid_q = '0' or rsp_ready_i = '1' else '0';
  snapshot_ready_o <= snapshot_ready_s;

  rsp_valid_o <= rsp_valid_q;
  rsp_data_o <= rsp_data_q;

  p_main : process(clk_i)
  begin
    if rising_edge(clk_i) then
      if rst_ni = '0' then
        rsp_valid_q <= '0';
        rsp_data_q <= (others => '0');
      else
        if rsp_valid_q = '1' and rsp_ready_i = '1' then
          rsp_valid_q <= '0';
        end if;

        if snapshot_valid_i = '1' and snapshot_ready_s = '1' then
          rsp_data_q <= f_build_response(
            snapshot_seq_i,
            action_s,
            best_bid_px_i,
            best_bid_qty_i,
            best_ask_px_i,
            best_ask_qty_i,
            spread_1e4_i,
            imbalance_i
          );
          rsp_valid_q <= '1';
        end if;
      end if;
    end if;
  end process;
end architecture rtl;
