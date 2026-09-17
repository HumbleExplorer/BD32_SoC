vsim -c -voptargs=+acc tb_core_top -G ITCM_FILE=stall_test.dat
when {/tb_core_top/u_RISC_V_Core/load_use_flag == 1'b1} {
  echo "LOADUSE_FLAG @ $now"
}
when {/tb_core_top/u_RISC_V_Core/u_Pipeline_Ctrl/bus_ready == 1'b0} {
  echo "BUS_NOT_READY @ $now"
}
run 7500ns
quit -f
