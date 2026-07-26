# ============================================================
# 总线访问超时测试 (BUS_TIMEOUT_TEST)
# 用法: 在 script/soc_test/ 目录下执行
#   vsim -do run_bus_timeout_test.do
# 或:
#   D:\modeltech64_2020.4\win64\modelsim -do run_bus_timeout_test.do
# ============================================================

if [file exists "work"] {vdel -all}
vlib work
vmap work work

# 编译时注入 BUS_TIMEOUT_TEST 宏
vlog +define+BUS_TIMEOUT_TEST -f filelist.f

vsim -voptargs=+acc tb_soc_top
set NoQuitOnFinish 1
onbreak {resume}

# 关键信号波形
add wave -divider "Clock & Reset"
add wave sim:/tb_soc_top/clk
add wave sim:/tb_soc_top/rst_n
add wave sim:/tb_soc_top/download_done

add wave -divider "UART Download"
add wave sim:/tb_soc_top/u_SoC_top/u_apb_uart/download_en
add wave sim:/tb_soc_top/u_SoC_top/u_apb_uart/u_uart_download/current_state

add wave -divider "CPU Bus Access"
add wave sim:/tb_soc_top/u_SoC_top/u_RISC_V_Core/bus_transfer
add wave sim:/tb_soc_top/u_SoC_top/u_RISC_V_Core/bus_ready
add wave sim:/tb_soc_top/u_SoC_top/u_RISC_V_Core/bus_tran_done
add wave -radix hex sim:/tb_soc_top/u_SoC_top/u_RISC_V_Core/bus_resp
add wave -radix hex sim:/tb_soc_top/u_SoC_top/u_RISC_V_Core/bus_addr_q
add wave sim:/tb_soc_top/u_SoC_top/u_RISC_V_Core/bus_write_q
add wave sim:/tb_soc_top/u_SoC_top/u_RISC_V_Core/bus_error

add wave -divider "AXI_Lite_Master Timeout"
add wave -radix hex sim:/tb_soc_top/u_SoC_top/u_Bus_Access/u_AXI_Lite_Master/state
add wave -radix unsigned sim:/tb_soc_top/u_SoC_top/u_Bus_Access/u_AXI_Lite_Master/timeout_cnt
add wave sim:/tb_soc_top/u_SoC_top/u_Bus_Access/u_AXI_Lite_Master/bus_timeout
add wave -radix hex sim:/tb_soc_top/u_SoC_top/u_Bus_Access/u_AXI_Lite_Master/rsp_error

add wave -divider "Exception"
add wave -radix hex sim:/tb_soc_top/u_SoC_top/u_RISC_V_Core/exception_code_ex
add wave -radix hex sim:/tb_soc_top/u_SoC_top/u_RISC_V_Core/exception_val_ex
add wave sim:/tb_soc_top/u_SoC_top/u_RISC_V_Core/u_CSR_Reg_Access/exception_trap
add wave -radix hex sim:/tb_soc_top/u_SoC_top/u_RISC_V_Core/u_CSR_Reg_Access/mepc
add wave -radix hex sim:/tb_soc_top/u_SoC_top/u_RISC_V_Core/u_CSR_Reg_Access/mcause

add wave -divider "APB Timer (hung slave)"
add wave sim:/tb_soc_top/u_SoC_top/apb_psel[4]
add wave sim:/tb_soc_top/u_SoC_top/apb_penable
add wave sim:/tb_soc_top/u_SoC_top/apb_pready[4]

add wave -divider "GPIO Result"
add wave -radix hex sim:/tb_soc_top/u_SoC_top/u_apb_gpio/out_reg

add wave -divider "CPU Pipeline"
add wave -radix hex sim:/tb_soc_top/u_SoC_top/u_RISC_V_Core/inst_addr_if
add wave -radix hex sim:/tb_soc_top/u_SoC_top/u_RISC_V_Core/pc

# bus_timeout.uartbin ~2992 bytes → 下载约 260ms
# 下载 + 运行 + 超时(12.8us) + 异常处理 ≈ 270ms，留余量跑 300ms
run 300ms
