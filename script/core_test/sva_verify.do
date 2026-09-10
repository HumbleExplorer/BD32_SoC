# SVA 断言专项验证：memstress + timer_int 注入
# 目的：验证本轮新增 14 条 SVA 在高频中断场景下不误触发
# 用法: cd script/core_test && vsim -c -do sva_verify.do
quit -sim

if {[file exists work]} {file delete -force work}
vlib work
vmap work work

vlog -sv +define+CORE_TEST+CUSTOM_ASM+DIRECT_LOAD -f filelist.f

vsim -batch -voptargs=+acc -G ITCM_FILE=memstress.dat -G DTCM_FILE=memstress.dat tb_core_top

# timer_int 脉冲（40ns高/1500ns周期 ≈ 35.7MHz，与 memstress_run.do 同款）
force -freeze sim:/tb_core_top/timer_int 1 0 ns, 0 40 ns -repeat 1500 ns

run 2000us
quit -f
