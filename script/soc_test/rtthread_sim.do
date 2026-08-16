rem rtthread demo (lts-v3.1.x, default): DIRECT_LOAD rtthread_os_*.mem (built by build.py --rtthread)
if {[file exists "work"]} {file delete -force work}
vlib work
vmap work work
vlog -f filelist.f +define+DIRECT_LOAD \
    {+define+ITCM_FILE="rtthread_os_itcm.mem"} \
    {+define+DTCM_FILE="rtthread_os_dtcm.mem"}
vsim -batch -voptargs=+acc tb_soc_top
run 80ms
quit -f
