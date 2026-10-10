# UART LSR 跨拍断言专项验证（+define+ASSERT_MODULE）
# 目的：在有 UART TX 流量的场景下验证 a_uart_lsr_thre/empt 的 $past 并发断言
#       （跨拍信号必须用 $past 比较，当拍直比会假失败）
# 程序: hello（UART TX 密集，THRE/TEMT 高频翻转）
# 用法: cd script/soc_test && vsim -batch -do uart_lsr_verify.do
quit -sim

if {[file exists "../../build/msim/uart_lsr_verify/work"]} {file delete -force "../../build/msim/uart_lsr_verify/work"}
file mkdir ../../build/msim/uart_lsr_verify
vlib ../../build/msim/uart_lsr_verify/work
vmap work ../../build/msim/uart_lsr_verify/work

vlog -sv +define+DIRECT_LOAD+ASSERT_MODULE \
    +define+ITCM_FILE=\"hello_itcm.mem\" \
    +define+DTCM_FILE=\"hello_dtcm.mem\" \
    -f filelist.f

vsim -batch -voptargs=+acc tb_soc_top

# hello 打印 banner 需要若干毫秒（UART 115200），L2 断言全程在线
run 8ms

puts "UART_LSR_VERIFY: run complete —— 无 SVA Error 即通过"
quit -f
