vsim -c -voptargs=+acc tb_debug
vcd file dbg_mcause.vcd
vcd add /tb_debug/sys_clk
vcd add /tb_debug/dbg_dpc
vcd add /tb_debug/u_SoC_top/u_RISC_V_Core/u_CSR_Reg_Access/mcause
vcd add /tb_debug/u_SoC_top/u_RISC_V_Core/u_CSR_Reg_Access/mepc
vcd add /tb_debug/u_SoC_top/u_RISC_V_Core/trap_jump
run 1500ns
quit -f
