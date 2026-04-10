function trade_decision_model_tb()
% Self-check for the MATLAB response-frame wrapper.

[seq, action, best_bid_px, best_bid_qty, best_ask_px, best_ask_qty, spread_1e4, imbalance] = ...
    trade_decision_model(uint32(2), uint32(1850000), uint32(2500), uint32(1852000), uint32(1200));

assert(seq == uint32(2));
assert(action == uint32(1));
assert(best_bid_px == uint32(1850000));
assert(best_bid_qty == uint32(2500));
assert(best_ask_px == uint32(1852000));
assert(best_ask_qty == uint32(1200));
assert(spread_1e4 == uint32(2000));
assert(imbalance == int32(1300));

[~, action, ~, ~, ~, ~, spread_1e4, imbalance] = ...
    trade_decision_model(uint32(3), uint32(1850000), uint32(2500), uint32(1852000), uint32(3200));

assert(action == uint32(2));
assert(spread_1e4 == uint32(2000));
assert(imbalance == int32(-700));

disp('trade_decision_model_tb PASSED');

end
