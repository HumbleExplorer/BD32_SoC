# CoreMark 取指等待归因仿真（10 迭代短版 + IFU 内部信号 VCD）
# 用法: cd script/soc_test && vsim -batch -do coremark_fetch_attribution.do
quit -sim

if {[file exists work]} {file delete -force work}
vlib work
vmap work work

vlog -sv +define+DIRECT_LOAD \
    +define+ITCM_FILE=\"fetch_jump_test.dat  \" \
    +define+DTCM_FILE=\"fetch_jump_test.dat  \" \
    -f filelist.f

vsim -batch -voptargs=+acc tb_soc_top

set core /tb_soc_top/u_SoC_top/u_RISC_V_Core
vcd file coremark_fetch_c.vcd
vcd add $core/fetch_wait_if
vcd add $core/u_IFU_Buffer/can_issue
vcd add $core/u_IFU_Buffer/redirect
vcd add $core/u_IFU_Buffer/stall
vcd add $core/u_IFU_Buffer/zcmp_active
vcd add $core/u_IFU_Buffer/unaligned32
vcd add $core/u_IFU_Buffer/next_ready
vcd add $core/u_IFU_Buffer/cur_eff_valid
vcd add $core/u_IFU_Buffer/served_d
vcd add $core/u_IFU_Buffer/req_addr
vcd add $core/u_IFU_Buffer/cur_w_addr
vcd add $core/u_IFU_Buffer/pc_asm
vcd add $core/u_IFU_Buffer/fetch_addr
vcd add $core/u_IFU_Buffer/crossing
vcd add $core/u_IFU_Buffer/refill_now
vcd add $core/u_IFU_Buffer/can_issue
vcd add $core/inst_addr_o
vcd add $core/u_IFU_Buffer/have_cur
vcd add $core/u_IFU_Buffer/pc_asm
vcd add $core/u_IFU_Buffer/fetch_addr
vcd add $core/u_IFU_Buffer/crossing
vcd add $core/u_IFU_Buffer/refill_now
vcd add $core/u_IFU_Buffer/can_issue
vcd add $core/inst_addr_o
vcd add $core/inst_valid_if
vcd add $core/ctrl_jump_en
vcd add $core/branch_jump_en
vcd add $core/u_IFU_Buffer/predict_redirect
vcd add /tb_soc_top/sys_clk

# CoreMark 全程（10 迭代 ≈ 4.5M cycles = 45M ns）
run 150ms

puts "FETCH_ATTRIBUTION_RUN_DONE"
quit -f
