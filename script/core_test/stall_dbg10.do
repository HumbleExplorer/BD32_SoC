vsim -c -voptargs=+acc tb_core_top -G ITCM_FILE=stall_test.dat
run 11000ns
echo "=== mcountinhibit ==="
exa -radix hex /tb_core_top/u_RISC_V_Core/u_CSR_Reg_Access/mcountinhibit
echo "=== loaduse cnt ==="
exa -radix decimal /tb_core_top/u_RISC_V_Core/u_CSR_Reg_Access/mhpmcounter[12]
echo "=== pc ==="
exa -radix hex /tb_core_top/u_RISC_V_Core/u_IFU_Buffer/pc
quit -f
