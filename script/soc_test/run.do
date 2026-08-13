if {[file exists "work"]} {file delete -force work}
vlib work
vmap work work
vlog -f filelist.f
vsim -voptargs=+acc tb_soc_top
set NoQuitOnFinish 1
onbreak {resume}
#log /* -r
do wave.do
run 17ms
