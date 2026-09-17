vsim -c -voptargs=+acc tb_core_top -G ITCM_FILE=stall_test.dat
when {/tb_core_top/u_RISC_V_Core/hpm_valid == 1'b1 && /tb_core_top/u_RISC_V_Core/hpm_inst_type == 4'd6} {
  echo "MULDIV_HPM @ $now"
}
when {/tb_core_top/u_RISC_V_Core/u_OITF/retire_valid == 1'b1} {
  echo "OITF_RETIRE @ $now"
}
run 8200ns
quit -f
