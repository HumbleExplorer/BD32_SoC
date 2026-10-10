# UART 中断收发闭环仿真（uart_irq demo：RDA 收行 + THRE 回显 ×3 → GPIO 签名）
# 用法: cd script/soc_test && vsim -batch -do run_uart_irq.do
quit -sim

if {[file exists "../../build/msim/uart_irq/work"]} {file delete -force "../../build/msim/uart_irq/work"}
file mkdir ../../build/msim/uart_irq
vlib ../../build/msim/uart_irq/work
vmap work ../../build/msim/uart_irq/work

vlog -sv +define+DIRECT_LOAD +define+UART_IRQ_TEST \
    +define+ITCM_FILE=\"uart_irq_os_itcm.mem\" \
    +define+DTCM_FILE=\"uart_irq_os_dtcm.mem\" \
    -f filelist.f

vsim -batch -voptargs=+acc tb_soc_top

run 60 ms
quit -f
