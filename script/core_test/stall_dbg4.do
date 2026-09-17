vsim -c -voptargs=+acc tb_core_top -G ITCM_FILE=stall_test.dat
run 5300ns
echo "=== T5.3us pc ==="
exa -radix hex /tb_core_top/u_RISC_V_Core/u_IFU_Buffer/pc
run 700ns
echo "=== T6.0us pc / loaduse ==="
exa -radix hex /tb_core_top/u_RISC_V_Core/u_IFU_Buffer/pc
exa -radix decimal /tb_core_top/u_RISC_V_Core/u_CSR_Reg_Access/mhpmcounter[12]
run 500ns
echo "=== T6.5us pc / loaduse ==="
exa -radix hex /tb_core_top/u_RISC_V_Core/u_IFU_Buffer/pc
exa -radix decimal /tb_core_top/u_RISC_V_Core/u_CSR_Reg_Access/mhpmcounter[12]
run 500ns
echo "=== T7.0us pc / loaduse ==="
exa -radix hex /tb_core_top/u_RISC_V_Core/u_IFU_Buffer/pc
exa -radix decimal /tb_core_top/u_RISC_V_Core/u_CSR_Reg_Access/mhpmcounter[12]
quit -f
