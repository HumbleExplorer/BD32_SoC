rem rtthread demo + 故障窗口 trace：先跑 60ms 再开 VCD（绕过 1GB 截断），只抓 60-80ms
if {[file exists "../../build/msim/rtthread_sim_fail_trace/work"]} {file delete -force "../../build/msim/rtthread_sim_fail_trace/work"}
file mkdir ../../build/msim/rtthread_sim_fail_trace
vlib ../../build/msim/rtthread_sim_fail_trace/work
vmap work ../../build/msim/rtthread_sim_fail_trace/work
vlog -f filelist.f +define+DIRECT_LOAD \
    {+define+ITCM_FILE="rtthread_os_itcm.mem"} \
    {+define+DTCM_FILE="rtthread_os_dtcm.mem"}
vsim -batch -voptargs=+acc tb_soc_top
run 60ms
vcd file ../../logs/fail_trace.vcd
vcd add /tb_soc_top/u_SoC_top/u_RISC_V_Core/u_DTCM/clk
vcd add /tb_soc_top/u_SoC_top/u_RISC_V_Core/pc
vcd add /tb_soc_top/u_SoC_top/u_RISC_V_Core/inst_ex
vcd add /tb_soc_top/u_SoC_top/u_RISC_V_Core/access_addr_ex
vcd add /tb_soc_top/u_SoC_top/u_RISC_V_Core/access_en_ex
vcd add /tb_soc_top/u_SoC_top/u_RISC_V_Core/dtcm_addr_sba
vcd add /tb_soc_top/u_SoC_top/u_RISC_V_Core/dtcm_rdata
vcd add /tb_soc_top/u_SoC_top/u_RISC_V_Core/tcm_rvalid
vcd add /tb_soc_top/u_SoC_top/u_RISC_V_Core/func3_expanded_data
vcd add /tb_soc_top/u_SoC_top/u_RISC_V_Core/reg_rd_wdata_mem
vcd add /tb_soc_top/u_SoC_top/u_RISC_V_Core/reg_rd_wen_mem
vcd add /tb_soc_top/u_SoC_top/u_RISC_V_Core/reg_rd_wdata_selected_mem
vcd add /tb_soc_top/u_SoC_top/u_RISC_V_Core/reg_rd_waddr_mem
vcd add /tb_soc_top/u_SoC_top/u_RISC_V_Core/u_CSR_Reg_Access/mcause
vcd add /tb_soc_top/u_SoC_top/u_RISC_V_Core/u_CSR_Reg_Access/reg_rd_wen
vcd add /tb_soc_top/u_SoC_top/u_RISC_V_Core/u_CSR_Reg_Access/reg_rd_waddr
vcd add /tb_soc_top/u_SoC_top/u_RISC_V_Core/u_CSR_Reg_Access/reg_rd_wdata
vcd add /tb_soc_top/u_SoC_top/u_RISC_V_Core/alu_op1_forward
vcd add /tb_soc_top/u_SoC_top/u_RISC_V_Core/dtcm_wdata_sba
vcd add /tb_soc_top/u_SoC_top/u_RISC_V_Core/access_wr_ex
vcd add /tb_soc_top/u_SoC_top/u_RISC_V_Core/alu_op2_forward
vcd add /tb_soc_top/u_SoC_top/u_RISC_V_Core/alu_op1_from_id_ex
vcd add /tb_soc_top/u_SoC_top/u_RISC_V_Core/ex_mem_stall
vcd add /tb_soc_top/u_SoC_top/u_RISC_V_Core/ex_mem_flush
vcd add /tb_soc_top/u_SoC_top/u_RISC_V_Core/u_Pipeline_Ctrl/id_ex_flush
vcd add /tb_soc_top/u_SoC_top/u_RISC_V_Core/u_Pipeline_Ctrl/id_ex_stall
run 20ms
quit -f
