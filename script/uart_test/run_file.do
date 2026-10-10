quit -sim
if {[file exists "../../build/msim/uart_file/work"]} {file delete -force "../../build/msim/uart_file/work"}
file mkdir ../../build/msim/uart_file
vlib ../../build/msim/uart_file/work
vmap work ../../build/msim/uart_file/work
vlog -sv -f filelist_file.f
vsim -batch -voptargs=+acc tb_uart_dl_file
run 200ms
quit -f
