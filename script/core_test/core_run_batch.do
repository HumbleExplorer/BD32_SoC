if {[file exists "work"]} {file delete -force work}
vlib work
vmap work work
vlog +define+DIRECT_LOAD +define+CORE_TEST +define+CUSTOM_ASM -f filelist.f
vopt tb_core_top -o tb_core_opt +acc
vsim -t 1ps work.tb_core_opt
run 100us
quit -f
