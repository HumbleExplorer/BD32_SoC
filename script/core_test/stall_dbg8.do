vsim -c -voptargs=+acc tb_core_top -G ITCM_FILE=stall_test.dat
run 8200ns
echo "=== array[5] MULDIV 0xB08 ==="
exa -radix decimal /tb_core_top/u_RISC_V_Core/u_CSR_Reg_Access/mhpmcounter[5]
echo "=== pc ==="
exa -radix hex /tb_core_top/u_RISC_V_Core/u_IFU_Buffer/pc
quit -f
