vsim -c -voptargs=+acc tb_core_top -G ITCM_FILE=zcmp_popret_ra.dat
run 700ns
echo "=== regs at 700ns: sp x3 t0 a0 x26 x27 ==="
examine -radix h /tb_core_top/u_RISC_V_Core/u_RegFile/regs[2]
examine -radix h /tb_core_top/u_RISC_V_Core/u_RegFile/regs[3]
examine -radix h /tb_core_top/u_RISC_V_Core/u_RegFile/regs[5]
examine -radix h /tb_core_top/u_RISC_V_Core/u_RegFile/regs[10]
examine -radix h /tb_core_top/u_RISC_V_Core/u_RegFile/regs[26]
examine -radix h /tb_core_top/u_RISC_V_Core/u_RegFile/regs[27]
quit -f
