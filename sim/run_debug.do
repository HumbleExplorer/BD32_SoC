# BD32 Debug + SBA 仿真脚本 (ModelSim)
# 用法: 在 sim/ 目录下执行 vsim -do run_debug.do

# 退出已有仿真
quit -sim

# 重建 work 库
if {[file exists work]} {
    vdel -all -lib work
}
vlib work

# 编译顺序：配置 → 公共 → Core → Bus → Periph → Debug → SoC → TB
set RTL ../rtl

vlog -sv +incdir+$RTL $RTL/SoC_Config.sv
vlog -sv +incdir+$RTL $RTL/RV32_Inst_Define.sv

# Common
vlog -sv +incdir+$RTL $RTL/Common/once_pulse_gen.sv
vlog -sv +incdir+$RTL $RTL/Common/Compare_Tree.sv
vlog -sv +incdir+$RTL $RTL/Common/async_fifo.sv
vlog -sv +incdir+$RTL $RTL/Common/sync_fifo.sv
vlog -sv +incdir+$RTL $RTL/Common/Clock/Cdc_Pulse.sv
vlog -sv +incdir+$RTL $RTL/Common/Clock/Cdc_Sync.sv
vlog -sv +incdir+$RTL $RTL/Common/Clock/clk_div_dynamic.sv
vlog -sv +incdir+$RTL $RTL/Common/Clock/clk_div_static.sv

# Core - Mul_Div
vlog -sv +incdir+$RTL $RTL/Core/Mul_Div/booth4code.sv
vlog -sv +incdir+$RTL $RTL/Core/Mul_Div/cla_4bit.sv
vlog -sv +incdir+$RTL $RTL/Core/Mul_Div/compressor42.sv
vlog -sv +incdir+$RTL $RTL/Core/Mul_Div/pg_gen.sv
vlog -sv +incdir+$RTL $RTL/Core/Mul_Div/cla.sv
vlog -sv +incdir+$RTL $RTL/Core/Mul_Div/divider.sv
vlog -sv +incdir+$RTL $RTL/Core/Mul_Div/multiplier.sv
vlog -sv +incdir+$RTL $RTL/Core/Mul_Div/mul_div.sv

# Core
vlog -sv +incdir+$RTL $RTL/Core/ITCM.sv
vlog -sv +incdir+$RTL $RTL/Core/DTCM.sv
vlog -sv +incdir+$RTL $RTL/Core/BootROM.sv
vlog -sv +incdir+$RTL $RTL/Core/IF_ID.sv
vlog -sv +incdir+$RTL $RTL/Core/ID_EX.sv
vlog -sv +incdir+$RTL $RTL/Core/EX_MEM.sv
vlog -sv +incdir+$RTL $RTL/Core/MEM_WB.sv
vlog -sv +incdir+$RTL $RTL/Core/OITF.sv
vlog -sv +incdir+$RTL $RTL/Core/PC_counter.sv
vlog -sv +incdir+$RTL $RTL/Core/Decoder.sv
vlog -sv +incdir+$RTL $RTL/Core/Executer.sv
vlog -sv +incdir+$RTL $RTL/Core/RegFile.sv
vlog -sv +incdir+$RTL $RTL/Core/CSR_Reg_Access.sv
vlog -sv +incdir+$RTL $RTL/Core/Pipeline_Ctrl.sv
vlog -sv +incdir+$RTL $RTL/Core/Data_Hazard_Forward.sv
vlog -sv +incdir+$RTL $RTL/Core/Dynamic_Branch_Predictor.sv
vlog -sv +incdir+$RTL $RTL/Core/Mem_Access.sv
vlog -sv +incdir+$RTL $RTL/Core/RISC_V_Core.sv

# Bus
vlog -sv +incdir+$RTL $RTL/Bus/Bus_Access.sv
vlog -sv +incdir+$RTL $RTL/Bus/AXI_Lite_Master.sv
vlog -sv +incdir+$RTL $RTL/Bus/AXI_APB_Bridge.sv
vlog -sv +incdir+$RTL $RTL/Bus/APB_Master.sv
vlog -sv +incdir+$RTL $RTL/Bus/AXI_Interconnect.sv
vlog -sv +incdir+$RTL $RTL/Bus/APB_Interconnect.sv
vlog -sv +incdir+$RTL $RTL/Bus/axi_err_slave.sv

# Peripherals
vlog -sv +incdir+$RTL $RTL/Periph/CLINT.sv
vlog -sv +incdir+$RTL $RTL/Periph/apb_gpio.sv
vlog -sv +incdir+$RTL $RTL/Periph/plic/PLIC.sv
vlog -sv +incdir+$RTL $RTL/Periph/plic/plic_gateway.sv
vlog -sv +incdir+$RTL $RTL/Periph/plic/plic_target.sv
vlog -sv +incdir+$RTL $RTL/Periph/uart/uart_clk_div.sv
vlog -sv +incdir+$RTL $RTL/Periph/uart/nco_baudgen.sv
vlog -sv +incdir+$RTL $RTL/Periph/uart/uart_download.sv
vlog -sv +incdir+$RTL $RTL/Periph/uart/uart_rx.sv
vlog -sv +incdir+$RTL $RTL/Periph/uart/uart_tx.sv
vlog -sv +incdir+$RTL $RTL/Periph/uart/apb_uart.sv
vlog -sv +incdir+$RTL $RTL/Periph/timer/apb_timer.sv
vlog -sv +incdir+$RTL $RTL/Periph/timer/basic_timer.sv
vlog -sv +incdir+$RTL $RTL/Periph/timer/timer_ic_oc.sv

# Debug
vlog -sv +incdir+$RTL $RTL/Debug/jtag_tap.sv
vlog -sv +incdir+$RTL $RTL/Debug/debug_cdc.sv
vlog -sv +incdir+$RTL $RTL/Debug/debug_dm.sv
vlog -sv +incdir+$RTL $RTL/Debug/debug_top.sv

# SoC Top
vlog -sv +incdir+$RTL $RTL/SoC_top.sv

# Testbench
vlog -sv +incdir+$RTL tb_debug.sv

# vopt 优化 + 运行仿真
vopt tb_debug -o tb_debug_opt +acc
vsim -t 1ps work.tb_debug_opt
run -all
