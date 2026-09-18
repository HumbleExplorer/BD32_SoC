vlog -f filelist.f +define+DIRECT_LOAD +define+CORE_TEST +define+CUSTOM_ASM +define+HPM_AUDIT +define+HPM_AUDIT_TRACE
vsim -c -voptargs=+acc tb_core_top -G ITCM_FILE=hpm_audit_test.dat
run 3ms
quit -f
