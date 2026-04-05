function [rsp_seq, rsp_action, rsp_price_1e4, rsp_qty] = trade_decision_model(seq_no, sym_side, price_1e4, qty)
% HDL-friendly placeholder strategy matching the hand-written VHDL core.
% rsp_action: 0=noop, 1=buy, 2=sell

buy_qty_threshold = uint32(2000);
sell_qty_threshold = uint32(2000);
side_code = bitshift(uint32(sym_side), -24);

rsp_seq = uint32(seq_no);
rsp_action = uint32(0);
rsp_price_1e4 = uint32(price_1e4);
rsp_qty = uint32(qty);

if side_code == uint32(1) && uint32(qty) >= buy_qty_threshold
    rsp_action = uint32(1);
elseif side_code == uint32(2) && uint32(qty) >= sell_qty_threshold
    rsp_action = uint32(2);
end

end
