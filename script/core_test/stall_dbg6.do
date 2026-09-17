vsim -c -voptargs=+acc tb_core_top -G ITCM_FILE=stall_test.dat
run 8100ns
echo "=== oitf counter ==="
exa -radix decimal /tb_core_top/u_RISC_V_Core/u_CSR_Reg_Access/mhpmcounter[13]
echo "=== muldiv counter 0xB08 ==="
exa -radix decimal /tb_core_top/u_RISC_V_Core/u_CSR_Reg_Access/mhpmcounter[3]
echo "=== oitf_stall ==="
exa -radix bin /tb_core_top/u_RISC_V_Core/oitf_stall
echo "=== oitf cnt ==="
exa -radix decimal /tb_core_top/u_RISC_V_Core/u_OITF/cnt
echo "=== pc ==="
exa -radix hex /tb_core_top/u_RISC_V_Core/u_IFU_Buffer/pc
quit -f
