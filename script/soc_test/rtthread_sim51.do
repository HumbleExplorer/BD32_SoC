rem rtthread demo (v5.1.0): DIRECT_LOAD rtthread51_os_*.mem (built by build.py --rtthread --rtthread-version 51)
if {[file exists "work"]} {file delete -force work}
vlib work
vmap work work
vlog -f filelist.f +define+DIRECT_LOAD \
    {+define+ITCM_FILE="rtthread51_os_itcm.mem"} \
    {+define+DTCM_FILE="rtthread51_os_dtcm.mem"}
vsim -batch -voptargs=+acc tb_soc_top
run 80ms
quit -f
