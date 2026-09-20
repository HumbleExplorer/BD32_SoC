# fetch 停顿归因仿真（10 迭代 C 配置 coremark，分类 fetch_wait 成因）
# 用法: cd script/soc_test && vsim -batch -do fetch_cause.do
quit -sim

if {[file exists work]} {file delete -force work}
vlib work
vmap work work

vlog -sv +define+DIRECT_LOAD \
    +define+ITCM_FILE=\"sim10_c_gcc_itcm.mem\" \
    +define+DTCM_FILE=\"sim10_c_gcc_dtcm.mem\" \
    -f filelist.f

vsim -batch -voptargs=+acc tb_soc_top

set core /tb_soc_top/u_SoC_top/u_RISC_V_Core
vcd file fetch_cause.vcd
vcd add $core/clk
vcd add $core/rst_n
vcd add $core/u_IFU_Buffer/fetch_wait_o
vcd add $core/u_IFU_Buffer/can_issue
vcd add $core/u_IFU_Buffer/unaligned32
vcd add $core/u_IFU_Buffer/next_ready
vcd add $core/u_IFU_Buffer/have_cur
vcd add $core/u_IFU_Buffer/refill_now
vcd add $core/u_IFU_Buffer/cur_eff_valid
vcd add $core/u_IFU_Buffer/redirect
vcd add $core/u_IFU_Buffer/predict_redirect
vcd add $core/u_IFU_Buffer/stall
vcd add $core/u_IFU_Buffer/zcmp_active
vcd add $core/u_IFU_Buffer/zcmp_consume
vcd add $core/u_IFU_Buffer/pc_asm

run 20000 us
quit -f
