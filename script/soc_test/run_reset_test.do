# ============================================================
# 复位后重新下载测试 (RESET_REDOWNLOAD_TEST)
# 用法: 在 script/soc_test/ 目录下执行
#   vsim -do run_reset_test.do
# 或在 top_tb.bat 中改为:
#   <ModelSim 安装目录>\win64\modelsim -do run_reset_test.do
# ============================================================

if [file exists "work"] {vdel -all}
vlib work
vmap work work

# 编译时注入 RESET_REDOWNLOAD_TEST 宏
vlog +define+RESET_REDOWNLOAD_TEST -f filelist.f

vsim -voptargs=+acc tb_soc_top
set NoQuitOnFinish 1
onbreak {resume}

# 关键信号波形
add wave -divider "Clock & Reset"
add wave sim:/tb_soc_top/clk
add wave sim:/tb_soc_top/rst_n
add wave sim:/tb_soc_top/download_en
add wave sim:/tb_soc_top/reset_phase

add wave -divider "UART Download"
add wave sim:/tb_soc_top/u_SoC_top/u_apb_uart/download_en
add wave sim:/tb_soc_top/u_SoC_top/u_apb_uart/u_uart_download/current_state
add wave sim:/tb_soc_top/u_SoC_top/u_apb_uart/u_uart_download/byte_cnt
add wave sim:/tb_soc_top/u_SoC_top/u_apb_uart/u_uart_download/word_count
add wave sim:/tb_soc_top/download_done

add wave -divider "CPU Pipeline"
add wave -radix hex sim:/tb_soc_top/u_SoC_top/u_RISC_V_Core/inst_addr_if
add wave sim:/tb_soc_top/u_SoC_top/u_RISC_V_Core/bus_transfer
add wave sim:/tb_soc_top/u_SoC_top/u_RISC_V_Core/bus_ready
add wave sim:/tb_soc_top/u_SoC_top/u_RISC_V_Core/oitf_stall

add wave -divider "OITF"
add wave sim:/tb_soc_top/u_SoC_top/u_RISC_V_Core/u_OITF/empty
add wave sim:/tb_soc_top/u_SoC_top/u_RISC_V_Core/u_OITF/full
add wave -radix hex sim:/tb_soc_top/u_SoC_top/u_RISC_V_Core/u_OITF/rd_ptr
add wave -radix hex sim:/tb_soc_top/u_SoC_top/u_RISC_V_Core/u_OITF/wr_ptr

add wave -divider "GPIO"
add wave -radix hex sim:/tb_soc_top/gpio_io
add wave sim:/tb_soc_top/u_SoC_top/u_apb_gpio/gpio_i

add wave -divider "AXI Bus"
add wave -radix hex sim:/tb_soc_top/u_SoC_top/u_RISC_V_Core/bus_load_waddr
add wave sim:/tb_soc_top/u_SoC_top/u_RISC_V_Core/bus_sel

# blink.uartbin ~2924 bytes → 每次下载约 254ms
# 两次下载 + 运行时间 + 超时 ≈ 600ms
run 600ms
