if [file exists "work"] {vdel -all}
vlib work
vmap work work
vlog +define+GPIO_SIM -f filelist.f
vsim -voptargs=+acc tb_apb_gpio
set NoQuitOnFinish 1
onbreak {resume}
#log /* -r
#do wave.do
run 10us