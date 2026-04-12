function action = strategy(best_bid_px, best_bid_qty, best_ask_px, best_ask_qty, spread_1e4, imbalance)
% HDL-friendly book-driven strategy.
% action: uint32(0)=NOOP, uint32(1)=BUY, uint32(2)=SELL

imbalance_threshold = int32(500);
max_spread_1e4 = uint32(25000);

action = uint32(0);

if uint32(best_bid_qty) == uint32(0) || uint32(best_ask_qty) == uint32(0)
    return;
end

if uint32(best_ask_px) <= uint32(best_bid_px)
    return;
end

if uint32(spread_1e4) > max_spread_1e4
    return;
end

imbalance_i32 = int32(imbalance);

if imbalance_i32 >= imbalance_threshold
    action = uint32(1);
elseif imbalance_i32 <= -imbalance_threshold
    action = uint32(2);
end

end
