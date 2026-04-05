function trade_decision_model_tb()
% Simple MATLAB self-check for the placeholder strategy model.

[seq, action, price, qty] = trade_decision_model(uint32(11), uint32(hex2dec('01415041')), uint32(1850000), uint32(2500));
assert(seq == uint32(11));
assert(action == uint32(1));
assert(price == uint32(1850000));
assert(qty == uint32(2500));

[~, action, ~, ~] = trade_decision_model(uint32(12), uint32(hex2dec('0246534D')), uint32(4150000), uint32(2200));
assert(action == uint32(2));

[~, action, ~, ~] = trade_decision_model(uint32(13), uint32(hex2dec('014C5354')), uint32(1750000), uint32(800));
assert(action == uint32(0));

disp('trade_decision_model_tb PASSED');

end
