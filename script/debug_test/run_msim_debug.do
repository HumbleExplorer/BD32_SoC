# BD32 Debug headless regression (tb_debug)
# Run from script/debug_test so that ../../test_data relative paths in
# SoC_Config.sv (mrom.dat / coremark .mem) resolve correctly:
#   vsim -batch -do run_msim_debug.do
# Optional env overrides (file name relative to test_data/soc/c/):
#   BD32_ITCM_FILE / BD32_DTCM_FILE, e.g. set BD32_ITCM_FILE=hello_itcm.mem
if {[file exists "work"]} {file delete -force work}
vlib work
vmap work work
set vlog_defs ""
if {[info exists env(BD32_ITCM_FILE)] && $env(BD32_ITCM_FILE) ne ""} {
    append vlog_defs " +define+ITCM_FILE=\"$env(BD32_ITCM_FILE)\""
}
if {[info exists env(BD32_DTCM_FILE)] && $env(BD32_DTCM_FILE) ne ""} {
    append vlog_defs " +define+DTCM_FILE=\"$env(BD32_DTCM_FILE)\""
}
vlog -f filelist.f $vlog_defs
vopt tb_debug -o tb_debug_opt +acc
vsim -t 1ps work.tb_debug_opt
run -all
quit -f
