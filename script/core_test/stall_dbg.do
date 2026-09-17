vsim -c -voptargs=+acc tb_core_top -G ITCM_FILE=stall_test.dat
run 300us
echo "=== x27 ==="
exa -radix hex /tb_core_top/x27
echo "=== pc ==="
exa -radix hex /tb_core_top/u_RISC_V_Core/u_IFU_Buffer/pc
echo "=== mcause ==="
exa -radix hex /tb_core_top/u_RISC_V_Core/u_CSR_Reg_Access/mcause
echo "=== mepc ==="
exa -radix hex /tb_core_top/u_RISC_V_Core/u_CSR_Reg_Access/mepc
quit -f
