if {[file exists "work"]} {file delete -force work}
vlib work
vmap work work
vlog +define+DIRECT_LOAD +define+CORE_TEST -f filelist.f
vsim -voptargs=+acc tb_core_top
set NoQuitOnFinish 1
onbreak {resume}
#log /* -r
#do wave.do
run 10us