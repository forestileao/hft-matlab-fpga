function [rsp_seq, rsp_action, rsp_best_bid_px, rsp_best_bid_qty, rsp_best_ask_px, rsp_best_ask_qty, rsp_spread_1e4, rsp_imbalance] = trade_decision_model(seq_no, best_bid_px, best_bid_qty, best_ask_px, best_ask_qty)
% HDL-friendly response-frame wrapper for the book-driven strategy.

rsp_seq = uint32(seq_no);
rsp_best_bid_px = uint32(best_bid_px);
rsp_best_bid_qty = uint32(best_bid_qty);
rsp_best_ask_px = uint32(best_ask_px);
rsp_best_ask_qty = uint32(best_ask_qty);

if uint32(best_bid_qty) ~= uint32(0) && uint32(best_ask_qty) ~= uint32(0) && uint32(best_ask_px) >= uint32(best_bid_px)
    rsp_spread_1e4 = uint32(best_ask_px) - uint32(best_bid_px);
else
    rsp_spread_1e4 = uint32(0);
end

rsp_imbalance = int32(best_bid_qty) - int32(best_ask_qty);
rsp_action = strategy(rsp_best_bid_px, rsp_best_bid_qty, rsp_best_ask_px, rsp_best_ask_qty, rsp_spread_1e4, rsp_imbalance);

end
