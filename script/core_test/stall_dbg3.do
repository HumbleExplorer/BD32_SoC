vsim -c -voptargs=+acc tb_core_top -G ITCM_FILE=stall_test.dat
run 7000ns
echo "=== loaduse ==="
exa -radix hex /tb_core_top/u_RISC_V_Core/u_CSR_Reg_Access/mhpmcounter[12]
echo "=== oitf ==="
exa -radix hex /tb_core_top/u_RISC_V_Core/u_CSR_Reg_Access/mhpmcounter[13]
echo "=== fetch ==="
exa -radix hex /tb_core_top/u_RISC_V_Core/u_CSR_Reg_Access/mhpmcounter[14]
echo "=== pc ==="
exa -radix hex /tb_core_top/u_RISC_V_Core/u_IFU_Buffer/pc
quit -f
