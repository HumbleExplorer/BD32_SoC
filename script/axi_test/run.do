# AXI 互联链验证仿真（BFM → AXI_Interconnect → 桥/APB 桩 + err_slave×2）
# 用例：APB 回环 / 随机等待态压力 / PSLVERR→SLVERR / err 段 OKAY / 桥超时 / 未路由段有界超时
# 用法: cd script/axi_test && vsim -batch -do run.do
quit -sim

if {[file exists "../../build/msim/axi_test/work"]} {file delete -force "../../build/msim/axi_test/work"}
file mkdir ../../build/msim/axi_test
vlib ../../build/msim/axi_test/work
vmap work ../../build/msim/axi_test/work

vlog -f filelist.f

vsim -batch -voptargs=+acc tb_axi_interconnect

run 8 ms
quit -f
