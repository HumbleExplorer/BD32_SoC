rem rtthread demo (v5.1.0 + picolibc): DIRECT_LOAD rtthread51_picolibc_os_*.mem
if {[file exists "../../build/msim/rtthread_sim51_pico/work"]} {file delete -force "../../build/msim/rtthread_sim51_pico/work"}
file mkdir ../../build/msim/rtthread_sim51_pico
vlib ../../build/msim/rtthread_sim51_pico/work
vmap work ../../build/msim/rtthread_sim51_pico/work
vlog -f filelist.f +define+DIRECT_LOAD \
    {+define+ITCM_FILE="rtthread51_picolibc_os_itcm.mem"} \
    {+define+DTCM_FILE="rtthread51_picolibc_os_dtcm.mem"}
vsim -batch -voptargs=+acc tb_soc_top
run 80ms
quit -f
