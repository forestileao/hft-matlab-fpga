library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity hft_trade_engine is
  generic (
    G_ADDR_WIDTH         : natural := 13;
    G_DEPTH              : natural := 64;
    G_SLOT_WORDS         : natural := 8;
    G_NUM_SYMBOLS        : natural := 8;
    G_BOOK_DEPTH         : natural := 8;
    G_IMBALANCE_THRESHOLD : natural := 500;
    G_MAX_SPREAD_1E4      : natural := 25000;
    G_CLOCK_HZ            : natural := 50000000
  );
  port (
    clk_i     : in  std_logic;
    rst_ni    : in  std_logic;

    mm_addr_i  : in  std_logic_vector(G_ADDR_WIDTH - 1 downto 0);
    mm_wr_i    : in  std_logic;
    mm_rd_i    : in  std_logic;
    mm_wdata_i : in  std_logic_vector(31 downto 0);
    mm_rdata_o : out std_logic_vector(31 downto 0);
    mm_ready_o : out std_logic
  );
end entity;

architecture rtl of hft_trade_engine is
  subtype t_u64 is unsigned(63 downto 0);
  type t_timestamp_fifo is array (0 to G_DEPTH - 1) of t_u64;

  signal cmd_valid_s : std_logic;
  signal cmd_data_s  : std_logic_vector(G_SLOT_WORDS * 32 - 1 downto 0);
  signal cmd_ready_s : std_logic;

  signal rsp_valid_s : std_logic;
  signal rsp_data_s  : std_logic_vector(G_SLOT_WORDS * 32 - 1 downto 0);
  signal rsp_ready_s : std_logic;

  signal perf_reset_s : std_logic;
  signal cycle_q      : t_u64 := (others => '0');
  signal ts_fifo_q    : t_timestamp_fifo := (others => (others => '0'));
  signal ts_head_q    : unsigned(15 downto 0) := (others => '0');
  signal ts_tail_q    : unsigned(15 downto 0) := (others => '0');
  signal ts_count_q   : unsigned(15 downto 0) := (others => '0');
  signal rsp_tracked_q : std_logic := '0';

  signal perf_count_q    : unsigned(31 downto 0) := (others => '0');
  signal perf_last_lat_q : unsigned(31 downto 0) := (others => '0');
  signal perf_min_lat_q  : unsigned(31 downto 0) := (others => '0');
  signal perf_max_lat_q  : unsigned(31 downto 0) := (others => '0');
  signal perf_sum_lat_q  : t_u64 := (others => '0');
  signal perf_cmd_stall_q : unsigned(31 downto 0) := (others => '0');
  signal perf_rsp_stall_q : unsigned(31 downto 0) := (others => '0');

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

  function f_sat_inc(v : unsigned) return unsigned is
    variable all_ones_v : unsigned(v'range) := (others => '1');
  begin
    if v = all_ones_v then
      return v;
    end if;
    return v + 1;
  end function;
begin
  u_bridge : entity work.arm_fpga_shared_stream_bridge
    generic map (
      G_ADDR_WIDTH => G_ADDR_WIDTH,
      G_DEPTH      => G_DEPTH,
      G_SLOT_WORDS => G_SLOT_WORDS
    )
    port map (
      clk_i       => clk_i,
      rst_ni      => rst_ni,
      mm_addr_i   => mm_addr_i,
      mm_wr_i     => mm_wr_i,
      mm_rd_i     => mm_rd_i,
      mm_wdata_i  => mm_wdata_i,
      mm_rdata_o  => mm_rdata_o,
      mm_ready_o  => mm_ready_o,
      cmd_valid_o => cmd_valid_s,
      cmd_data_o  => cmd_data_s,
      cmd_ready_i => cmd_ready_s,
      rsp_valid_i => rsp_valid_s,
      rsp_data_i  => rsp_data_s,
      rsp_ready_o => rsp_ready_s,
      perf_reset_o            => perf_reset_s,
      perf_clock_hz_i         => std_logic_vector(to_unsigned(G_CLOCK_HZ, 32)),
      perf_count_i            => std_logic_vector(perf_count_q),
      perf_last_lat_cycles_i  => std_logic_vector(perf_last_lat_q),
      perf_min_lat_cycles_i   => std_logic_vector(perf_min_lat_q),
      perf_max_lat_cycles_i   => std_logic_vector(perf_max_lat_q),
      perf_sum_lat_cycles_i   => std_logic_vector(perf_sum_lat_q),
      perf_cmd_stall_cycles_i => std_logic_vector(perf_cmd_stall_q),
      perf_rsp_stall_cycles_i => std_logic_vector(perf_rsp_stall_q)
    );

  u_decision : entity work.trade_decision_core
    generic map (
      G_SLOT_WORDS          => G_SLOT_WORDS,
      G_NUM_SYMBOLS         => G_NUM_SYMBOLS,
      G_BOOK_DEPTH          => G_BOOK_DEPTH,
      G_IMBALANCE_THRESHOLD => G_IMBALANCE_THRESHOLD,
      G_MAX_SPREAD_1E4      => G_MAX_SPREAD_1E4
    )
    port map (
      clk_i       => clk_i,
      rst_ni      => rst_ni,
      cmd_valid_i => cmd_valid_s,
      cmd_data_i  => cmd_data_s,
      cmd_ready_o => cmd_ready_s,
      rsp_valid_o => rsp_valid_s,
      rsp_data_o  => rsp_data_s,
      rsp_ready_i => rsp_ready_s
    );

  p_perf : process(clk_i)
    variable cmd_accept_v : boolean;
    variable rsp_produced_v : boolean;
    variable rsp_consumed_v : boolean;
    variable latency_v    : t_u64;
    variable latency32_v  : unsigned(31 downto 0);
    variable next_head_v  : unsigned(15 downto 0);
    variable next_tail_v  : unsigned(15 downto 0);
    variable next_count_v : unsigned(15 downto 0);
    variable next_rsp_tracked_v : std_logic;
  begin
    if rising_edge(clk_i) then
      if rst_ni = '0' or perf_reset_s = '1' then
        cycle_q <= (others => '0');
        ts_fifo_q <= (others => (others => '0'));
        ts_head_q <= (others => '0');
        ts_tail_q <= (others => '0');
        ts_count_q <= (others => '0');
        rsp_tracked_q <= '0';
        perf_count_q <= (others => '0');
        perf_last_lat_q <= (others => '0');
        perf_min_lat_q <= (others => '0');
        perf_max_lat_q <= (others => '0');
        perf_sum_lat_q <= (others => '0');
        perf_cmd_stall_q <= (others => '0');
        perf_rsp_stall_q <= (others => '0');
      else
        cycle_q <= cycle_q + 1;

        cmd_accept_v := cmd_valid_s = '1' and cmd_ready_s = '1';
        rsp_produced_v := rsp_valid_s = '1' and rsp_tracked_q = '0';
        rsp_consumed_v := rsp_valid_s = '1' and rsp_ready_s = '1';
        next_head_v := ts_head_q;
        next_tail_v := ts_tail_q;
        next_count_v := ts_count_q;
        next_rsp_tracked_v := rsp_tracked_q;

        if cmd_valid_s = '1' and cmd_ready_s = '0' then
          perf_cmd_stall_q <= f_sat_inc(perf_cmd_stall_q);
        end if;

        if rsp_valid_s = '1' and rsp_ready_s = '0' then
          perf_rsp_stall_q <= f_sat_inc(perf_rsp_stall_q);
        end if;

        if cmd_accept_v and ts_count_q < to_unsigned(G_DEPTH, ts_count_q'length) then
          ts_fifo_q(to_integer(ts_head_q)) <= cycle_q;
          next_head_v := f_inc_wrap(ts_head_q);
          next_count_v := next_count_v + 1;
        end if;

        -- Measure pure FPGA pipeline latency when the response first becomes
        -- visible, not when the ARM side finally drains the RX ring.
        if rsp_produced_v and ts_count_q /= 0 then
          latency_v := (cycle_q - ts_fifo_q(to_integer(ts_tail_q))) + 1;
          latency32_v := latency_v(31 downto 0);

          next_tail_v := f_inc_wrap(ts_tail_q);
          next_count_v := next_count_v - 1;

          perf_count_q <= f_sat_inc(perf_count_q);
          perf_last_lat_q <= latency32_v;
          if perf_count_q = 0 or latency32_v < perf_min_lat_q then
            perf_min_lat_q <= latency32_v;
          end if;
          if latency32_v > perf_max_lat_q then
            perf_max_lat_q <= latency32_v;
          end if;
          perf_sum_lat_q <= perf_sum_lat_q + resize(latency32_v, perf_sum_lat_q'length);
          next_rsp_tracked_v := '1';
        end if;

        if rsp_consumed_v then
          next_rsp_tracked_v := '0';
        end if;

        ts_head_q <= next_head_v;
        ts_tail_q <= next_tail_v;
        ts_count_q <= next_count_v;
        rsp_tracked_q <= next_rsp_tracked_v;
      end if;
    end if;
  end process;
end architecture rtl;
