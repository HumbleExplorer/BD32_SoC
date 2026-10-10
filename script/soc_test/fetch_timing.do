# 取指时序图取材仿真（C 配置 coremark，跳过启动段抓内核中段 1.5ms）
# 用法: cd script/soc_test && vsim -batch -do fetch_timing.do
quit -sim

if {[file exists "../../build/msim/fetch_timing/work"]} {file delete -force "../../build/msim/fetch_timing/work"}
file mkdir ../../build/msim/fetch_timing
vlib ../../build/msim/fetch_timing/work
vmap work ../../build/msim/fetch_timing/work

vlog -sv +define+DIRECT_LOAD \
    +define+ITCM_FILE=\"sim10_c_gcc_itcm.mem\" \
    +define+DTCM_FILE=\"sim10_c_gcc_dtcm.mem\" \
    -f filelist.f

vsim -batch -voptargs=+acc tb_soc_top

set core /tb_soc_top/u_SoC_top/u_RISC_V_Core
set ifu  $core/u_IFU_Buffer

# 先跑 20ms（无波形），再开 VCD 抓内核中段
run 20000 us

vcd file fetch_timing.vcd
vcd add $core/clk
vcd add $core/rst_n
vcd add $ifu/pc
vcd add $ifu/pc_asm
vcd add $ifu/req_addr
vcd add $ifu/fetch_addr
vcd add $ifu/cur_w_addr
vcd add $ifu/refill_now
vcd add $ifu/next_ready
vcd add $ifu/can_issue
vcd add $ifu/crossing
vcd add $ifu/unaligned32
vcd add $ifu/have_cur
vcd add $ifu/cur_eff_valid
vcd add $ifu/served_d
vcd add $ifu/redirect
vcd add $ifu/jump_en
vcd add $ifu/predict_redirect
vcd add $ifu/stall
vcd add $ifu/req_fwd
vcd add $ifu/fetch_wait_o
vcd add $core/inst_valid_if

run 1500 us
quit -f
