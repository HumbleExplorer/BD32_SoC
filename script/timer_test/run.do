if {[file exists "work"]} {file delete -force work}
vlib work
vmap work work
vlog +define+TIMER_SIM -f filelist.f
vsim -voptargs=+acc tb_apb_timer
set NoQuitOnFinish 1
onbreak {resume}
#log /* -r
#do wave.do
run 10us
