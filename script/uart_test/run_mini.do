# UART 下载链路最小直连测试（秒级）
quit -sim
if {[file exists "../../build/msim/uart_mini/work"]} {file delete -force "../../build/msim/uart_mini/work"}
file mkdir ../../build/msim/uart_mini
vlib ../../build/msim/uart_mini/work
vmap work ../../build/msim/uart_mini/work
vlog -sv -f filelist_mini.f
vsim -batch -voptargs=+acc tb_uart_dl_mini
run 5ms
quit -f
