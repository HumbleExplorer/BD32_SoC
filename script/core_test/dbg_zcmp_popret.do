vsim -c -voptargs=+acc tb_core_top -G ITCM_FILE=zcmp_popret_ra.dat
vcd file dbg_zcmp2.vcd
vcd add /tb_core_top/clk
vcd add /tb_core_top/u_RISC_V_Core/u_IFU_Buffer/pc_asm
vcd add /tb_core_top/u_RISC_V_Core/u_IFU_Buffer/inst_valid_o
vcd add /tb_core_top/u_RISC_V_Core/u_IFU_Buffer/inst_o
vcd add /tb_core_top/u_RISC_V_Core/u_IFU_Buffer/zcmp_busy
vcd add /tb_core_top/u_RISC_V_Core/u_IFU_Buffer/zcmp_micro_valid
vcd add /tb_core_top/u_RISC_V_Core/u_IFU_Buffer/zcmp_capture
vcd add /tb_core_top/u_RISC_V_Core/ctrl_jump_en
vcd add /tb_core_top/u_RISC_V_Core/ctrl_jump_addr
vcd add /tb_core_top/x3
vcd add /tb_core_top/x26
vcd add /tb_core_top/x27
vcd add /tb_core_top/u_RISC_V_Core/u_RegFile/regs[2]
run 900ns
quit -f
