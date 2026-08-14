# BD32 Core 裸核仿真脚本 (ModelSim)
# 用法: 在 script/core_test/ 目录下执行 vsim -c -do run_core.do

quit -sim

if {[file exists work]} {
    vdel -all -lib work
}
vlib work

set RTL ../../rtl
set DEFS "+define+CORE_TEST+CUSTOM_ASM+DIRECT_LOAD"

vlog -sv $DEFS +incdir+$RTL $RTL/SoC_Config.sv
vlog -sv $DEFS +incdir+$RTL $RTL/RV32_Inst_Define.sv

# Common
vlog -sv $DEFS +incdir+$RTL $RTL/Common/once_pulse_gen.sv
vlog -sv $DEFS +incdir+$RTL $RTL/Common/Compare_Tree.sv
vlog -sv $DEFS +incdir+$RTL $RTL/Common/async_fifo.sv
vlog -sv $DEFS +incdir+$RTL $RTL/Common/sync_fifo.sv
vlog -sv $DEFS +incdir+$RTL $RTL/Common/Clock/Cdc_Pulse.sv
vlog -sv $DEFS +incdir+$RTL $RTL/Common/Clock/Cdc_Sync.sv
vlog -sv $DEFS +incdir+$RTL $RTL/Common/Clock/clk_div_dynamic.sv
vlog -sv $DEFS +incdir+$RTL $RTL/Common/Clock/clk_div_static.sv

# Core - Mul_Div
vlog -sv $DEFS +incdir+$RTL $RTL/Core/Mul_Div/booth4code.sv
vlog -sv $DEFS +incdir+$RTL $RTL/Core/Mul_Div/cla_4bit.sv
vlog -sv $DEFS +incdir+$RTL $RTL/Core/Mul_Div/compressor42.sv
vlog -sv $DEFS +incdir+$RTL $RTL/Core/Mul_Div/pg_gen.sv
vlog -sv $DEFS +incdir+$RTL $RTL/Core/Mul_Div/cla.sv
vlog -sv $DEFS +incdir+$RTL $RTL/Core/Mul_Div/divider.sv
vlog -sv $DEFS +incdir+$RTL $RTL/Core/Mul_Div/multiplier.sv
vlog -sv $DEFS +incdir+$RTL $RTL/Core/Mul_Div/mul_div.sv

# Core
vlog -sv $DEFS +incdir+$RTL $RTL/Core/ITCM.sv
vlog -sv $DEFS +incdir+$RTL $RTL/Core/DTCM.sv
vlog -sv $DEFS +incdir+$RTL $RTL/Core/BootROM.sv
vlog -sv $DEFS +incdir+$RTL $RTL/Core/IF_ID.sv
vlog -sv $DEFS +incdir+$RTL $RTL/Core/ID_EX.sv
vlog -sv $DEFS +incdir+$RTL $RTL/Core/EX_MEM.sv
vlog -sv $DEFS +incdir+$RTL $RTL/Core/MEM_WB.sv
vlog -sv $DEFS +incdir+$RTL $RTL/Core/OITF.sv
vlog -sv $DEFS +incdir+$RTL $RTL/Core/PC_counter.sv
vlog -sv $DEFS +incdir+$RTL $RTL/Core/Decoder.sv
vlog -sv $DEFS +incdir+$RTL $RTL/Core/Executer.sv
vlog -sv $DEFS +incdir+$RTL $RTL/Core/RegFile.sv
vlog -sv $DEFS +incdir+$RTL $RTL/Core/CSR_Reg_Access.sv
vlog -sv $DEFS +incdir+$RTL $RTL/Core/Pipeline_Ctrl.sv
vlog -sv $DEFS +incdir+$RTL $RTL/Core/Data_Hazard_Forward.sv
vlog -sv $DEFS +incdir+$RTL $RTL/Core/Dynamic_Branch_Predictor.sv
vlog -sv $DEFS +incdir+$RTL $RTL/Core/Mem_Access.sv
vlog -sv $DEFS +incdir+$RTL $RTL/Core/RISC_V_Core.sv

# Testbench
vlog -sv $DEFS +incdir+$RTL ../../tb/tb_core_top.sv

# vopt + run
vopt tb_core_top -o tb_core_opt +acc
vsim -t 1ps work.tb_core_opt
run -all
