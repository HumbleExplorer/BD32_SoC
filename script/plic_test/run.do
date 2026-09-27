if {[file exists "../../build/msim/run/work"]} {file delete -force "../../build/msim/run/work"}
file mkdir ../../build/msim/run
vlib ../../build/msim/run/work
vmap work ../../build/msim/run/work
vlog -f filelist.f
vsim -voptargs=+acc tb_apb_plic
set NoQuitOnFinish 1
onbreak {resume}
#log /* -r
#do wave.do
run 1ms
