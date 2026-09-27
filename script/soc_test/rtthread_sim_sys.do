rem rtthread demo (lts-v3.1.x, default): DIRECT_LOAD rtthread_os_*.mem (built by build.py --rtthread)
if {[file exists "../../build/msim/rtthread_sim_sys/work"]} {file delete -force "../../build/msim/rtthread_sim_sys/work"}
file mkdir ../../build/msim/rtthread_sim_sys
vlib ../../build/msim/rtthread_sim_sys/work
vmap work ../../build/msim/rtthread_sim_sys/work
vlog -f filelist.f +define+DIRECT_LOAD+ASSERT_SYS \
    {+define+ITCM_FILE="rtthread_os_itcm.mem"} \
    {+define+DTCM_FILE="rtthread_os_dtcm.mem"}
vsim -batch -voptargs=+acc tb_soc_top
run 80ms
quit -f
