vsim -c -voptargs=+acc tb_core_top -G ITCM_FILE=stall_test.dat
run 7135ns
echo "=== loaduse 0xB0F ==="
exa -radix hex /tb_core_top/u_RISC_V_Core/u_CSR_Reg_Access/mhpmcounter[12]
echo "=== oitf 0xB10 ==="
exa -radix hex /tb_core_top/u_RISC_V_Core/u_CSR_Reg_Access/mhpmcounter[13]
echo "=== fetch 0xB11 ==="
exa -radix hex /tb_core_top/u_RISC_V_Core/u_CSR_Reg_Access/mhpmcounter[14]
echo "=== pc ==="
exa -radix hex /tb_core_top/u_RISC_V_Core/u_IFU_Buffer/pc
quit -f
