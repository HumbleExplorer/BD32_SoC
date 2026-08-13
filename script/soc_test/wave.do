onerror {resume}
onerror {resume}
quietly WaveActivateNextPane {} 0

# ============ TOP: clk / rst / LED / PWM ============
add wave -noupdate -group TOP /tb_soc_top/clk
add wave -noupdate -group TOP /tb_soc_top/rst_n
add wave -noupdate -group TOP /tb_soc_top/gpio_io
add wave -noupdate -group TOP /tb_soc_top/timer_channel_io
add wave -noupdate -group TOP /tb_soc_top/uart_tx

# ============ PIPELINE PCs + valid ============
add wave -noupdate -group PC /tb_soc_top/u_SoC_top/u_RISC_V_Core/inst_addr_if
add wave -noupdate -group PC /tb_soc_top/u_SoC_top/u_RISC_V_Core/inst_addr_id
add wave -noupdate -group PC /tb_soc_top/u_SoC_top/u_RISC_V_Core/inst_addr_ex
add wave -noupdate -group PC /tb_soc_top/u_SoC_top/u_RISC_V_Core/inst_addr_mem
add wave -noupdate -group PC /tb_soc_top/u_SoC_top/u_RISC_V_Core/inst_addr_wb
add wave -noupdate -group PC /tb_soc_top/u_SoC_top/u_RISC_V_Core/u_IF_ID/valid_o
add wave -noupdate -group PC /tb_soc_top/u_SoC_top/u_RISC_V_Core/u_ID_EX/valid_o
add wave -noupdate -group PC /tb_soc_top/u_SoC_top/u_RISC_V_Core/u_EX_MEM/valid_o
add wave -noupdate -group PC /tb_soc_top/u_SoC_top/u_RISC_V_Core/u_MEM_WB/valid_o

# ============ TRAP/INT: mepc capture & jump ============
add wave -noupdate -group TRAP /tb_soc_top/u_SoC_top/u_RISC_V_Core/trap_jump
add wave -noupdate -group TRAP /tb_soc_top/u_SoC_top/u_RISC_V_Core/trap_jump_exc
add wave -noupdate -group TRAP /tb_soc_top/u_SoC_top/u_RISC_V_Core/mret_req
add wave -noupdate -group TRAP /tb_soc_top/u_SoC_top/u_RISC_V_Core/u_CSR_Reg_Access/int_trap_jump_n
add wave -noupdate -group TRAP /tb_soc_top/u_SoC_top/u_RISC_V_Core/u_CSR_Reg_Access/int_trap_jump
add wave -noupdate -group TRAP /tb_soc_top/u_SoC_top/u_RISC_V_Core/u_CSR_Reg_Access/int_waiting_jump
add wave -noupdate -group TRAP /tb_soc_top/u_SoC_top/u_RISC_V_Core/u_CSR_Reg_Access/waiting_int
add wave -noupdate -group TRAP /tb_soc_top/u_SoC_top/u_RISC_V_Core/u_CSR_Reg_Access/mepc
add wave -noupdate -group TRAP /tb_soc_top/u_SoC_top/u_RISC_V_Core/u_CSR_Reg_Access/mcause
add wave -noupdate -group TRAP /tb_soc_top/u_SoC_top/u_RISC_V_Core/u_CSR_Reg_Access/mstatus
add wave -noupdate -group TRAP /tb_soc_top/u_SoC_top/u_RISC_V_Core/u_CSR_Reg_Access/mie

# ============ FLUSH / STALL ============
add wave -noupdate -group FLUSH /tb_soc_top/u_SoC_top/u_RISC_V_Core/u_Pipeline_Ctrl/if_id_flush
add wave -noupdate -group FLUSH /tb_soc_top/u_SoC_top/u_RISC_V_Core/u_Pipeline_Ctrl/id_ex_flush
add wave -noupdate -group FLUSH /tb_soc_top/u_SoC_top/u_RISC_V_Core/u_Pipeline_Ctrl/ex_mem_flush
add wave -noupdate -group FLUSH /tb_soc_top/u_SoC_top/u_RISC_V_Core/u_Pipeline_Ctrl/mem_wb_flush
add wave -noupdate -group FLUSH /tb_soc_top/u_SoC_top/u_RISC_V_Core/u_Pipeline_Ctrl/oitf_flush
add wave -noupdate -group FLUSH /tb_soc_top/u_SoC_top/u_RISC_V_Core/u_Pipeline_Ctrl/if_id_stall
add wave -noupdate -group FLUSH /tb_soc_top/u_SoC_top/u_RISC_V_Core/u_Pipeline_Ctrl/id_ex_stall
add wave -noupdate -group FLUSH /tb_soc_top/u_SoC_top/u_RISC_V_Core/u_Pipeline_Ctrl/ex_mem_stall
add wave -noupdate -group FLUSH /tb_soc_top/u_SoC_top/u_RISC_V_Core/u_Pipeline_Ctrl/mem_wb_stall
add wave -noupdate -group FLUSH /tb_soc_top/u_SoC_top/u_RISC_V_Core/u_Pipeline_Ctrl/oitf_stall

# ============ SP (x2) & writeback ============
add wave -noupdate -group SP /tb_soc_top/u_SoC_top/u_RISC_V_Core/u_RegFile/regs(2)
add wave -noupdate -group SP /tb_soc_top/u_SoC_top/u_RISC_V_Core/reg_rd_wen
add wave -noupdate -group SP /tb_soc_top/u_SoC_top/u_RISC_V_Core/reg_rd_waddr
add wave -noupdate -group SP /tb_soc_top/u_SoC_top/u_RISC_V_Core/reg_rd_wdata

# ============ MEM rvalid (Bug B key) ============
add wave -noupdate -group MEM /tb_soc_top/u_SoC_top/u_RISC_V_Core/u_Mem_Access/dtcm_rvalid_q
add wave -noupdate -group MEM /tb_soc_top/u_SoC_top/u_RISC_V_Core/u_Mem_Access/dtcm_rvalid
add wave -noupdate -group MEM /tb_soc_top/u_SoC_top/u_RISC_V_Core/u_Mem_Access/dtcm_sel
add wave -noupdate -group MEM /tb_soc_top/u_SoC_top/u_RISC_V_Core/u_Mem_Access/access_en
add wave -noupdate -group MEM /tb_soc_top/u_SoC_top/u_RISC_V_Core/u_Mem_Access/access_addr
add wave -noupdate -group MEM /tb_soc_top/u_SoC_top/u_RISC_V_Core/u_Mem_Access/access_wr
add wave -noupdate -group MEM /tb_soc_top/u_SoC_top/u_RISC_V_Core/reg_rd_wen_selected_mem
add wave -noupdate -group MEM /tb_soc_top/u_SoC_top/u_RISC_V_Core/reg_rd_waddr_selected_mem
add wave -noupdate -group MEM /tb_soc_top/u_SoC_top/u_RISC_V_Core/func3_expanded_data

# ============ TIMER/PLIC (PWM + IRQ source) ============
add wave -noupdate -group TIMER /tb_soc_top/u_SoC_top/u_apb_timer/basic_timer_inst/timer_cnt
add wave -noupdate -group TIMER /tb_soc_top/u_SoC_top/u_apb_timer/basic_timer_inst/prescale_cnt
add wave -noupdate -group TIMER /tb_soc_top/u_SoC_top/u_apb_timer/basic_timer_inst/timer_expired
add wave -noupdate -group TIMER /tb_soc_top/u_SoC_top/u_apb_timer/basic_timer_inst/timer_expired_req
add wave -noupdate -group TIMER /tb_soc_top/u_SoC_top/u_PLIC/irq_o
add wave -noupdate -group TIMER /tb_soc_top/u_SoC_top/external_int

TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {16300000 ns} 0}
quietly wave cursor active 1
configure wave -namecolwidth 300
configure wave -valuecolwidth 100
configure wave -justifyvalue left
configure wave -signalnamewidth 1
configure wave -snapdistance 10
configure wave -datasetprefix 0
configure wave -rowmargin 4
configure wave -childrowmargin 2
configure wave -gridoffset 0
configure wave -gridperiod 1
configure wave -griddelta 40
configure wave -timeline 0
configure wave -timelineunits ns
update
