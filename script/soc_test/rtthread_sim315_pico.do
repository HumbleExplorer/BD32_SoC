rem rtthread demo (lts-v3.1.x + picolibc): DIRECT_LOAD rtthread_picolibc_os_*.mem
rem (built by: python tools/build.py demos/rtthread --rtthread --picolibc)
if {[file exists "../../build/msim/rtthread_sim315_pico/work"]} {file delete -force "../../build/msim/rtthread_sim315_pico/work"}
file mkdir ../../build/msim/rtthread_sim315_pico
vlib ../../build/msim/rtthread_sim315_pico/work
vmap work ../../build/msim/rtthread_sim315_pico/work
vlog -f filelist.f +define+DIRECT_LOAD \
    {+define+ITCM_FILE="rtthread_picolibc_os_itcm.mem"} \
    {+define+DTCM_FILE="rtthread_picolibc_os_dtcm.mem"}
vsim -batch -voptargs=+acc tb_soc_top
run 80ms
quit -f
