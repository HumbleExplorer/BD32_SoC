if [file exists "work"] {vdel -all}
vlib work
vmap work work
vlog -f filelist.f
vsim -voptargs=+acc tb_apb_uart
set NoQuitOnFinish 1
onbreak {resume}
#log /* -r
#do wave.do
# UART 位级 TX/RX 测试使用真实波特率时序（115200 每字节约 87us），10us 不足以完成；至少需 500us
run 500us