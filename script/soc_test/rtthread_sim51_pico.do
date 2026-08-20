rem rtthread demo (v5.1.0 + picolibc): DIRECT_LOAD rtthread51_picolibc_os_*.mem
if {[file exists "work"]} {file delete -force work}
vlib work
vmap work work
vlog -f filelist.f +define+DIRECT_LOAD \
    {+define+ITCM_FILE="rtthread51_picolibc_os_itcm.mem"} \
    {+define+DTCM_FILE="rtthread51_picolibc_os_dtcm.mem"}
vsim -batch -voptargs=+acc tb_soc_top
run 80ms
quit -f
