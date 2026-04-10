function strategy_tb()
% Self-check for the HDL-friendly book-driven strategy.

action = strategy(uint32(1850000), uint32(2500), uint32(1852000), uint32(1200), uint32(2000), int32(1300));
assert(action == uint32(1));

action = strategy(uint32(1850000), uint32(2500), uint32(1852000), uint32(3200), uint32(2000), int32(-700));
assert(action == uint32(2));

action = strategy(uint32(1850000), uint32(2500), uint32(0), uint32(0), uint32(0), int32(2500));
assert(action == uint32(0));

action = strategy(uint32(1850000), uint32(2500), uint32(1905000), uint32(1200), uint32(55000), int32(1300));
assert(action == uint32(0));

disp('strategy_tb PASSED');

end
