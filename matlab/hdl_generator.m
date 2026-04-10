function hdl_generator()
% Generate VHDL for the strategy block without using the HDL Coder GUI.

source_dir = fileparts(mfilename('fullpath'));
out_dir = fullfile(source_dir, 'generated_hdl');

if exist(out_dir, 'dir') ~= 7
    mkdir(out_dir);
end

addpath(source_dir);
prev_dir = pwd;
cleanup_obj = onCleanup(@() cd(prev_dir)); %#ok<NASGU>
cd(out_dir);

hdlcfg = coder.config('hdl');
hdlcfg.TargetLanguage = 'VHDL';
hdlcfg.GenerateHDLTestBench = false;

args = { ...
    uint32(0), ... % best_bid_px
    uint32(0), ... % best_bid_qty
    uint32(0), ... % best_ask_px
    uint32(0), ... % best_ask_qty
    uint32(0), ... % spread_1e4
    int32(0)};     % imbalance

codegen -config hdlcfg strategy -args args

disp(['HDL generated into ', out_dir]);

end
