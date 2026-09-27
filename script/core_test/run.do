if {[file exists "../../build/msim/run/work"]} {file delete -force "../../build/msim/run/work"}
file mkdir ../../build/msim/run
vlib ../../build/msim/run/work
vmap work ../../build/msim/run/work
vlog +define+DIRECT_LOAD +define+CORE_TEST -f filelist.f
vsim -voptargs=+acc tb_core_top
set NoQuitOnFinish 1
onbreak {resume}
#log /* -r
#do wave.do
run 10us