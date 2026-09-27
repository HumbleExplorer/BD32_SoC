if {[file exists "../../build/msim/core_run_batch/work"]} {file delete -force "../../build/msim/core_run_batch/work"}
file mkdir ../../build/msim/core_run_batch
vlib ../../build/msim/core_run_batch/work
vmap work ../../build/msim/core_run_batch/work
vlog +define+DIRECT_LOAD +define+CORE_TEST +define+CUSTOM_ASM -f filelist.f
vopt tb_core_top -o tb_core_opt +acc
vsim -t 1ps work.tb_core_opt
run 100us
quit -f
