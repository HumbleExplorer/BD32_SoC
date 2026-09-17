vsim -c -voptargs=+acc tb_core_top -G ITCM_FILE=stall_test.dat
run 8200ns
echo "=== oitf ==="
exa -radix decimal /tb_core_top/u_RISC_V_Core/u_CSR_Reg_Access/mhpmcounter[13]
echo "=== 0xB08-mapped array idx4 muldiv ==="
exa -radix decimal /tb_core_top/u_RISC_V_Core/u_CSR_Reg_Access/mhpmcounter[4]
echo "=== pc ==="
exa -radix hex /tb_core_top/u_RISC_V_Core/u_IFU_Buffer/pc
quit -f
