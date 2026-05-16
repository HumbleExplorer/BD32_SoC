if [file exists "work"] {vdel -all}
vlib work
vmap work work
vlog +define+DIRECT_LOAD -f filelist.f
vsim -voptargs=+acc tb_soc_top
set NoQuitOnFinish 1
onbreak {resume}
#log /* -r
do wave.do
run 15ms
