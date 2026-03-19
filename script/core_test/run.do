if [file exists "work"] {vdel -all}
vlib work
vmap work work
vlog -f filelist.f
vsim -voptargs=+acc tb_core_top
set NoQuitOnFinish 1
onbreak {resume}
#log /* -r
#do wave.do
run 10us