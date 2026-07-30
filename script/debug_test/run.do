if [file exists "work"] {vdel -all}
vlib work
vmap work work
vlog -f filelist.f
vsim -voptargs=+acc tb_debug
set NoQuitOnFinish 1
onbreak {resume}
do wave.do
run 500us
