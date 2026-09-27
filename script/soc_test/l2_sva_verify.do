# L2 模块级断言专项验证（+define+ASSERT_MODULE）
# 目的：验证 L2 深化断言（plic_target 协议、apb_uart 帧/FIFO、SoC 中断映射等）
#       在中断密集场景下不误触发
# 程序: plic_irq（test_data/soc/c/ 下直接加载），CPU 主动轮询 PLIC claim/complete 位
#       驱动 u_PLIC 全路径；timer 脉冲由 APB Timer 外设软件配置产生
# 用法: cd script/soc_test && D:/modeltech64_2020.4/win64/vsim -c -do l2_sva_verify.do
quit -sim

if {[file exists "../../build/msim/l2_sva_verify/work"]} {file delete -force "../../build/msim/l2_sva_verify/work"}
file mkdir ../../build/msim/l2_sva_verify
vlib ../../build/msim/l2_sva_verify/work
vmap work ../../build/msim/l2_sva_verify/work

vlog -sv +define+DIRECT_LOAD+ASSERT_MODULE \
    +define+ITCM_FILE="plic_irq_itcm.mem" \
    +define+DTCM_FILE="plic_irq_dtcm.mem" \
    -f filelist.f

vsim -batch -voptargs=+acc tb_soc_top

# PLIC source 3 (timer_irq) 默认已被 plic_irq 程序配置为 pending+enable，
# 若跑偏（SVA 误报或程序没跑起来），观察 u_PLIC 层次确认
run 300us
# 兜底：若 plic_irq 程序未走 timer 源，force 一条 timer_irq 脉冲
# 驱动 u_PLIC 全路径（claim/complete/eip）
# vsim -batch 下 run 会阻塞推进到目标时间，$finish 终止仿真
force -freeze tb_soc_top.u_SoC_top.timer_irq 0
run 300us
# 每 100us 脉冲一次，覆盖 PLIC pending→claim→complete 周期
for {set i 0} {$i < 6} {incr i} {
    force tb_soc_top.u_SoC_top.timer_irq 1
    run 50us
    force tb_soc_top.u_SoC_top.timer_irq 0
    run 50us
}
run 200us
puts "L2_SVA_VERIFY COMPLETE"
quit -f
