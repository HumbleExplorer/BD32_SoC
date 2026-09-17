vsim -c -voptargs=+acc tb_debug
vcd file dbg_dpc.vcd
vcd add /tb_debug/sys_clk
vcd add /tb_debug/dbg_dpc
vcd add /tb_debug/dbg_halt_req
vcd add /tb_debug/dbg_halted
run 60us
quit -f
