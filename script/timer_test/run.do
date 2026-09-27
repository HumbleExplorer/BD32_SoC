if {[file exists "../../build/msim/run/work"]} {file delete -force "../../build/msim/run/work"}
file mkdir ../../build/msim/run
vlib ../../build/msim/run/work
vmap work ../../build/msim/run/work
vlog +define+TIMER_SIM -f filelist.f
vsim -voptargs=+acc tb_apb_timer
set NoQuitOnFinish 1
onbreak {resume}
#log /* -r
#do wave.do
run 10us
