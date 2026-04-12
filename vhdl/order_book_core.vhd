library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity order_book_core is
  generic (
    G_SLOT_WORDS  : natural := 8;
    G_NUM_SYMBOLS : natural := 8;
    G_BOOK_DEPTH  : natural := 8
  );
  port (
    clk_i : in std_logic;
    rst_ni : in std_logic;

    evt_valid_i : in std_logic;
    evt_data_i  : in std_logic_vector(G_SLOT_WORDS * 32 - 1 downto 0);
    evt_ready_o : out std_logic;

    snapshot_valid_o     : out std_logic;
    snapshot_seq_o       : out std_logic_vector(31 downto 0);
    snapshot_symbol_id_o : out std_logic_vector(31 downto 0);
    best_bid_px_o        : out std_logic_vector(31 downto 0);
    best_bid_qty_o       : out std_logic_vector(31 downto 0);
    best_ask_px_o        : out std_logic_vector(31 downto 0);
    best_ask_qty_o       : out std_logic_vector(31 downto 0);
    spread_1e4_o         : out std_logic_vector(31 downto 0);
    imbalance_o          : out std_logic_vector(31 downto 0);
    snapshot_ready_i     : in  std_logic
  );
end entity;

architecture rtl of order_book_core is
  constant C_EVENT_UPSERT_LEVEL : natural := 1;
  constant C_EVENT_DELETE_LEVEL : natural := 2;
  constant C_EVENT_RESET_BOOK   : natural := 3;

  constant C_SIDE_BUY  : natural := 1;
  constant C_SIDE_SELL : natural := 2;

  subtype t_u32 is unsigned(31 downto 0);
  type t_level_arr is array (0 to G_BOOK_DEPTH - 1) of t_u32;
  type t_side_matrix is array (0 to G_NUM_SYMBOLS - 1) of t_level_arr;

  signal bid_price_q : t_side_matrix := (others => (others => (others => '0')));
  signal bid_qty_q   : t_side_matrix := (others => (others => (others => '0')));
  signal ask_price_q : t_side_matrix := (others => (others => (others => '0')));
  signal ask_qty_q   : t_side_matrix := (others => (others => (others => '0')));

  signal snapshot_valid_q     : std_logic := '0';
  signal snapshot_seq_q       : std_logic_vector(31 downto 0) := (others => '0');
  signal snapshot_symbol_id_q : std_logic_vector(31 downto 0) := (others => '0');
  signal best_bid_px_q        : std_logic_vector(31 downto 0) := (others => '0');
  signal best_bid_qty_q       : std_logic_vector(31 downto 0) := (others => '0');
  signal best_ask_px_q        : std_logic_vector(31 downto 0) := (others => '0');
  signal best_ask_qty_q       : std_logic_vector(31 downto 0) := (others => '0');
  signal spread_1e4_q         : std_logic_vector(31 downto 0) := (others => '0');
  signal imbalance_q          : std_logic_vector(31 downto 0) := (others => '0');

  signal evt_ready_s : std_logic;

  function f_word(frame : std_logic_vector; idx : natural) return std_logic_vector is
    variable lsb : natural := idx * 32;
  begin
    return frame(lsb + 31 downto lsb);
  end function;

  procedure p_clear_side(
    variable prices_v : inout t_level_arr;
    variable qtys_v   : inout t_level_arr
  ) is
  begin
    for i in 0 to G_BOOK_DEPTH - 1 loop
      prices_v(i) := (others => '0');
      qtys_v(i) := (others => '0');
    end loop;
  end procedure;

  procedure p_delete_at(
    variable prices_v : inout t_level_arr;
    variable qtys_v   : inout t_level_arr;
    constant idx      : in natural
  ) is
  begin
    for i in 0 to G_BOOK_DEPTH - 2 loop
      if i >= idx then
        prices_v(i) := prices_v(i + 1);
        qtys_v(i) := qtys_v(i + 1);
      end if;
    end loop;
    prices_v(G_BOOK_DEPTH - 1) := (others => '0');
    qtys_v(G_BOOK_DEPTH - 1) := (others => '0');
  end procedure;

  procedure p_apply_level_update(
    variable prices_v  : inout t_level_arr;
    variable qtys_v    : inout t_level_arr;
    constant price_v   : in t_u32;
    constant qty_v     : in t_u32;
    constant is_delete : in boolean;
    constant desc_sort : in boolean
  ) is
    variable match_idx  : integer := -1;
    variable insert_idx : integer := -1;
  begin
    for i in 0 to G_BOOK_DEPTH - 1 loop
      if qtys_v(i) /= 0 and prices_v(i) = price_v then
        match_idx := i;
      end if;
    end loop;

    if match_idx /= -1 then
      if is_delete or qty_v = 0 then
        p_delete_at(prices_v, qtys_v, natural(match_idx));
      else
        qtys_v(natural(match_idx)) := qty_v;
      end if;
      return;
    end if;

    if is_delete or qty_v = 0 then
      return;
    end if;

    for i in 0 to G_BOOK_DEPTH - 1 loop
      if qtys_v(i) = 0 then
        insert_idx := i;
        exit;
      end if;

      if desc_sort then
        if price_v > prices_v(i) then
          insert_idx := i;
          exit;
        end if;
      else
        if price_v < prices_v(i) then
          insert_idx := i;
          exit;
        end if;
      end if;
    end loop;

    if insert_idx = -1 then
      return;
    end if;

    for i in G_BOOK_DEPTH - 1 downto 1 loop
      if i > natural(insert_idx) then
        prices_v(i) := prices_v(i - 1);
        qtys_v(i) := qtys_v(i - 1);
      end if;
    end loop;

    prices_v(natural(insert_idx)) := price_v;
    qtys_v(natural(insert_idx)) := qty_v;
  end procedure;
begin
  evt_ready_s <= '1' when snapshot_valid_q = '0' or snapshot_ready_i = '1' else '0';
  evt_ready_o <= evt_ready_s;

  snapshot_valid_o     <= snapshot_valid_q;
  snapshot_seq_o       <= snapshot_seq_q;
  snapshot_symbol_id_o <= snapshot_symbol_id_q;
  best_bid_px_o        <= best_bid_px_q;
  best_bid_qty_o       <= best_bid_qty_q;
  best_ask_px_o        <= best_ask_px_q;
  best_ask_qty_o       <= best_ask_qty_q;
  spread_1e4_o         <= spread_1e4_q;
  imbalance_o          <= imbalance_q;

  p_main : process(clk_i)
    variable v_bid_price   : t_side_matrix;
    variable v_bid_qty     : t_side_matrix;
    variable v_ask_price   : t_side_matrix;
    variable v_ask_qty     : t_side_matrix;
    variable seq_v         : std_logic_vector(31 downto 0);
    variable symbol_v      : std_logic_vector(31 downto 0);
    variable price_v       : t_u32;
    variable qty_v         : t_u32;
    variable event_type_v  : natural;
    variable side_v        : natural;
    variable symbol_idx_v  : integer;
    variable best_bid_px_v : t_u32;
    variable best_bid_qty_v : t_u32;
    variable best_ask_px_v : t_u32;
    variable best_ask_qty_v : t_u32;
    variable spread_v      : t_u32;
    variable imbalance_v   : signed(31 downto 0);
  begin
    if rising_edge(clk_i) then
      if rst_ni = '0' then
        bid_price_q <= (others => (others => (others => '0')));
        bid_qty_q <= (others => (others => (others => '0')));
        ask_price_q <= (others => (others => (others => '0')));
        ask_qty_q <= (others => (others => (others => '0')));
        snapshot_valid_q <= '0';
        snapshot_seq_q <= (others => '0');
        snapshot_symbol_id_q <= (others => '0');
        best_bid_px_q <= (others => '0');
        best_bid_qty_q <= (others => '0');
        best_ask_px_q <= (others => '0');
        best_ask_qty_q <= (others => '0');
        spread_1e4_q <= (others => '0');
        imbalance_q <= (others => '0');
      else
        if snapshot_valid_q = '1' and snapshot_ready_i = '1' then
          snapshot_valid_q <= '0';
        end if;

        if evt_valid_i = '1' and evt_ready_s = '1' then
          v_bid_price := bid_price_q;
          v_bid_qty := bid_qty_q;
          v_ask_price := ask_price_q;
          v_ask_qty := ask_qty_q;

          seq_v := f_word(evt_data_i, 0);
          symbol_v := f_word(evt_data_i, 1);
          price_v := unsigned(f_word(evt_data_i, 2));
          qty_v := unsigned(f_word(evt_data_i, 3));
          event_type_v := to_integer(unsigned(f_word(evt_data_i, 4)));
          side_v := to_integer(unsigned(f_word(evt_data_i, 5)));
          symbol_idx_v := to_integer(unsigned(symbol_v));

          best_bid_px_v := (others => '0');
          best_bid_qty_v := (others => '0');
          best_ask_px_v := (others => '0');
          best_ask_qty_v := (others => '0');
          spread_v := (others => '0');
          imbalance_v := (others => '0');

          if symbol_idx_v >= 0 and symbol_idx_v < G_NUM_SYMBOLS then
            if event_type_v = C_EVENT_RESET_BOOK then
              p_clear_side(v_bid_price(symbol_idx_v), v_bid_qty(symbol_idx_v));
              p_clear_side(v_ask_price(symbol_idx_v), v_ask_qty(symbol_idx_v));
            elsif side_v = C_SIDE_BUY then
              -- Reject crossed bids. A buy level at or above the current best ask
              -- would make the synthetic book internally inconsistent.
              if event_type_v = C_EVENT_DELETE_LEVEL or
                 v_ask_qty(symbol_idx_v)(0) = 0 or
                 price_v < v_ask_price(symbol_idx_v)(0) then
                p_apply_level_update(
                  v_bid_price(symbol_idx_v),
                  v_bid_qty(symbol_idx_v),
                  price_v,
                  qty_v,
                  event_type_v = C_EVENT_DELETE_LEVEL,
                  true
                );
              end if;
            elsif side_v = C_SIDE_SELL then
              -- Reject crossed asks for the same reason: best bid must remain
              -- strictly below best ask when both sides are present.
              if event_type_v = C_EVENT_DELETE_LEVEL or
                 v_bid_qty(symbol_idx_v)(0) = 0 or
                 price_v > v_bid_price(symbol_idx_v)(0) then
                p_apply_level_update(
                  v_ask_price(symbol_idx_v),
                  v_ask_qty(symbol_idx_v),
                  price_v,
                  qty_v,
                  event_type_v = C_EVENT_DELETE_LEVEL,
                  false
                );
              end if;
            end if;

            best_bid_px_v := v_bid_price(symbol_idx_v)(0);
            best_bid_qty_v := v_bid_qty(symbol_idx_v)(0);
            best_ask_px_v := v_ask_price(symbol_idx_v)(0);
            best_ask_qty_v := v_ask_qty(symbol_idx_v)(0);

            if best_bid_qty_v /= 0 and best_ask_qty_v /= 0 and best_ask_px_v > best_bid_px_v then
              spread_v := best_ask_px_v - best_bid_px_v;
            end if;

            imbalance_v := signed(best_bid_qty_v) - signed(best_ask_qty_v);
          end if;

          bid_price_q <= v_bid_price;
          bid_qty_q <= v_bid_qty;
          ask_price_q <= v_ask_price;
          ask_qty_q <= v_ask_qty;

          snapshot_seq_q <= seq_v;
          snapshot_symbol_id_q <= symbol_v;
          best_bid_px_q <= std_logic_vector(best_bid_px_v);
          best_bid_qty_q <= std_logic_vector(best_bid_qty_v);
          best_ask_px_q <= std_logic_vector(best_ask_px_v);
          best_ask_qty_q <= std_logic_vector(best_ask_qty_v);
          spread_1e4_q <= std_logic_vector(spread_v);
          imbalance_q <= std_logic_vector(imbalance_v);
          snapshot_valid_q <= '1';
        end if;
      end if;
    end if;
  end process;
end architecture rtl;
