if {[file exists "../../build/msim/run/work"]} {file delete -force "../../build/msim/run/work"}
file mkdir ../../build/msim/run
vlib ../../build/msim/run/work
vmap work ../../build/msim/run/work
vlog -f filelist.f
vsim -voptargs=+acc tb_debug
set NoQuitOnFinish 1
onbreak {resume}
do wave.do
run 500us
