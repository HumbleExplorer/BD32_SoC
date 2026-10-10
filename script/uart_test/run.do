if {[file exists "../../build/msim/run/work"]} {file delete -force "../../build/msim/run/work"}
file mkdir ../../build/msim/run
vlib ../../build/msim/run/work
vmap work ../../build/msim/run/work
vlog -f filelist.f
vsim -voptargs=+acc tb_apb_uart
set NoQuitOnFinish 1
onbreak {resume}
#log /* -r
#do wave.do
# UART 位级 TX/RX 测试使用真实波特率时序（115200 每字节约 87us）；全套寄存器用例
# 含 17 字节溢出压力与多点校验帧，总时长约 3.5ms，留裕量 8ms（TB 自 $finish）
run 8000us
