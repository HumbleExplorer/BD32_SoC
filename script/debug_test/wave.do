onerror {resume}
quietly WaveActivateNextPane {} 0

add wave -noupdate /tb_debug/sys_clk
add wave -noupdate /tb_debug/rst_n
add wave -noupdate /tb_debug/tck
add wave -noupdate /tb_debug/tms
add wave -noupdate /tb_debug/tdi
add wave -noupdate /tb_debug/tdo

add wave -noupdate -divider "Debug Control"
add wave -noupdate /tb_debug/dbg_halt_req
add wave -noupdate /tb_debug/dbg_halted
add wave -noupdate /tb_debug/dbg_resume_req
add wave -noupdate /tb_debug/dbg_step
add wave -noupdate /tb_debug/dbg_ebreakm

add wave -noupdate -divider "Debug RegFile"
add wave -noupdate /tb_debug/dbg_reg_we
add wave -noupdate -radix hex /tb_debug/dbg_reg_addr
add wave -noupdate -radix hex /tb_debug/dbg_reg_wdata
add wave -noupdate -radix hex /tb_debug/dbg_reg_rdata
add wave -noupdate -radix hex /tb_debug/dbg_dpc

add wave -noupdate -divider "DM Internal"
add wave -noupdate -radix hex /tb_debug/u_debug_top/u_dm/state
add wave -noupdate /tb_debug/u_debug_top/u_dm/rx_valid
add wave -noupdate -radix hex /tb_debug/u_debug_top/u_dm/rx_data_r
add wave -noupdate -radix hex /tb_debug/u_debug_top/u_dm/dmi_rsp_data
add wave -noupdate /tb_debug/u_debug_top/u_dm/need_resp
add wave -noupdate -radix hex /tb_debug/u_debug_top/u_dm/data0
add wave -noupdate -radix hex /tb_debug/u_debug_top/u_dm/dmcontrol_r

add wave -noupdate -divider "TAP Internal"
add wave -noupdate -radix hex /tb_debug/u_debug_top/u_tap/tap_state
add wave -noupdate -radix hex /tb_debug/u_debug_top/u_tap/ir_reg
add wave -noupdate -radix hex /tb_debug/u_debug_top/u_tap/shift_reg

TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {0 ns} 0}
configure wave -namecolwidth 250
configure wave -valuecolwidth 100
configure wave -timelineunits ns
update
