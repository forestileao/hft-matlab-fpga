library ieee;
use ieee.std_logic_1164.all;

entity hft_trade_engine_avalon_mm is
  generic (
    G_ADDR_WIDTH         : natural := 12;
    G_DEPTH              : natural := 64;
    G_SLOT_WORDS         : natural := 4;
    G_BUY_QTY_THRESHOLD  : natural := 2000;
    G_SELL_QTY_THRESHOLD : natural := 2000
  );
  port (
    clk_i   : in  std_logic;
    rst_ni  : in  std_logic;

    avs_chipselect_i  : in  std_logic;
    avs_address_i     : in  std_logic_vector(G_ADDR_WIDTH - 3 downto 0);
    avs_read_i        : in  std_logic;
    avs_write_i       : in  std_logic;
    avs_byteenable_i  : in  std_logic_vector(3 downto 0);
    avs_writedata_i   : in  std_logic_vector(31 downto 0);
    avs_readdata_o    : out std_logic_vector(31 downto 0);
    avs_waitrequest_o : out std_logic
  );
end entity;

architecture rtl of hft_trade_engine_avalon_mm is
  type t_state is (S_IDLE, S_ISSUE, S_WAIT, S_COMPLETE);

  signal state_q : t_state := S_IDLE;

  signal req_addr_q  : std_logic_vector(G_ADDR_WIDTH - 3 downto 0) := (others => '0');
  signal req_read_q  : std_logic := '0';
  signal req_write_q : std_logic := '0';
  signal req_wdata_q : std_logic_vector(31 downto 0) := (others => '0');
  signal read_data_q : std_logic_vector(31 downto 0) := (others => '0');

  signal mm_addr_s  : std_logic_vector(G_ADDR_WIDTH - 1 downto 0);
  signal mm_wr_s    : std_logic;
  signal mm_rd_s    : std_logic;
  signal mm_wdata_s : std_logic_vector(31 downto 0);
  signal mm_rdata_s : std_logic_vector(31 downto 0);
  signal mm_ready_s : std_logic;
begin
  u_engine : entity work.hft_trade_engine
    generic map (
      G_ADDR_WIDTH         => G_ADDR_WIDTH,
      G_DEPTH              => G_DEPTH,
      G_SLOT_WORDS         => G_SLOT_WORDS,
      G_BUY_QTY_THRESHOLD  => G_BUY_QTY_THRESHOLD,
      G_SELL_QTY_THRESHOLD => G_SELL_QTY_THRESHOLD
    )
    port map (
      clk_i      => clk_i,
      rst_ni     => rst_ni,
      mm_addr_i  => mm_addr_s,
      mm_wr_i    => mm_wr_s,
      mm_rd_i    => mm_rd_s,
      mm_wdata_i => mm_wdata_s,
      mm_rdata_o => mm_rdata_s,
      mm_ready_o => mm_ready_s
    );

  mm_addr_s  <= req_addr_q & "00";
  mm_wdata_s <= req_wdata_q;
  mm_wr_s    <= '1' when state_q = S_ISSUE and req_write_q = '1' else '0';
  mm_rd_s    <= '1' when state_q = S_ISSUE and req_read_q = '1' else '0';

  avs_readdata_o <= read_data_q;
  avs_waitrequest_o <= '0' when state_q = S_COMPLETE or
                                (state_q = S_IDLE and avs_chipselect_i = '0' and avs_read_i = '0' and avs_write_i = '0')
                       else '1';

  p_main : process(clk_i)
  begin
    if rising_edge(clk_i) then
      if rst_ni = '0' then
        state_q     <= S_IDLE;
        req_addr_q  <= (others => '0');
        req_read_q  <= '0';
        req_write_q <= '0';
        req_wdata_q <= (others => '0');
        read_data_q <= (others => '0');
      else
        case state_q is
          when S_IDLE =>
            if avs_chipselect_i = '1' and (avs_read_i = '1' or avs_write_i = '1') then
              req_addr_q  <= avs_address_i;
              req_read_q  <= avs_read_i;
              req_write_q <= avs_write_i;
              req_wdata_q <= avs_writedata_i;
              state_q     <= S_ISSUE;
            end if;

          when S_ISSUE =>
            state_q <= S_WAIT;

          when S_WAIT =>
            if mm_ready_s = '1' then
              if req_read_q = '1' then
                read_data_q <= mm_rdata_s;
              end if;
              state_q <= S_COMPLETE;
            end if;

          when S_COMPLETE =>
            req_read_q  <= '0';
            req_write_q <= '0';
            state_q     <= S_IDLE;
        end case;
      end if;
    end if;
  end process;
end architecture rtl;
