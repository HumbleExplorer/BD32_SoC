# BD32 Debug headless regression (tb_debug)
# Run from script/debug_test so that ../../test_data relative paths in
# SoC_Config.sv (mrom.dat / coremark .mem) resolve correctly:
#   vsim -batch -do run_msim_debug.do
if {[file exists "work"]} {file delete -force work}
vlib work
vmap work work
vlog -f filelist.f
vopt tb_debug -o tb_debug_opt +acc
vsim -t 1ps work.tb_debug_opt
run -all
quit -f
