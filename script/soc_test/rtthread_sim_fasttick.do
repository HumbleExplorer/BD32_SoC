rem rtthread demo + FAST TICK timer (35.7MHz)：压 CLINT mtime 异步边沿竞争窗（09-06 tidle 冻死 sim 复现配方）
if {[file exists "../../build/msim/rtthread_sim_fasttick/work"]} {file delete -force "../../build/msim/rtthread_sim_fasttick/work"}
file mkdir ../../build/msim/rtthread_sim_fasttick
vlib ../../build/msim/rtthread_sim_fasttick/work
vmap work ../../build/msim/rtthread_sim_fasttick/work
vlog -f filelist.f +define+DIRECT_LOAD \
    {+define+ITCM_FILE="rtthread_os_itcm.mem"} \
    {+define+DTCM_FILE="rtthread_os_dtcm.mem"}
vsim -batch -voptargs=+acc tb_soc_top
force -freeze sim:/tb_soc_top/timer_clk 1 0 ns, 0 14 ns -repeat 28 ns
run 80ms
quit -f
