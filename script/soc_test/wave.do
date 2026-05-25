onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate /tb_soc_top/*
add wave -noupdate /tb_soc_top/u_SoC_top/*
add wave -noupdate /tb_soc_top/u_SoC_top/u_apb_uart/*
add wave -noupdate /tb_soc_top/u_SoC_top/u_apb_uart/u_uart_download/*
add wave -noupdate /tb_soc_top/u_SoC_top/u_RISC_V_Core/*
add wave -noupdate /tb_soc_top/u_SoC_top/u_RISC_V_Core/u_Pipeline_Ctrl/*
add wave -noupdate /tb_soc_top/u_SoC_top/u_RISC_V_Core/u_Data_Hazard_Forward/*
add wave -noupdate /tb_soc_top/u_SoC_top/u_RISC_V_Core/u_Dynamic_Branch_Predictor/*
add wave -noupdate /tb_soc_top/u_SoC_top/u_RISC_V_Core/u_RegFile/*
add wave -noupdate /tb_soc_top/u_SoC_top/u_RISC_V_Core/u_Executer/*
add wave -noupdate /tb_soc_top/u_SoC_top/u_RISC_V_Core/u_Mem_Access/*
add wave -noupdate /tb_soc_top/u_SoC_top/u_RISC_V_Core/u_DTCM/*
add wave -noupdate /tb_soc_top/u_SoC_top/u_RISC_V_Core/u_CSR_Reg_Access/*
add wave -noupdate /tb_soc_top/u_SoC_top/u_PLIC/*
add wave -noupdate /tb_soc_top/u_SoC_top/u_AXI_Interconnect/*
add wave -noupdate /tb_soc_top/u_SoC_top/u_AXI_APB_Bridge/*
add wave -noupdate /tb_soc_top/u_SoC_top/u_Bus_Access/*
add wave -noupdate /tb_soc_top/u_SoC_top/u_Bus_Access/u_AXI_Lite_Master/*
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {198697 ps} 0}
quietly wave cursor active 1
configure wave -namecolwidth 524
configure wave -valuecolwidth 100
configure wave -justifyvalue left
configure wave -signalnamewidth 0
configure wave -snapdistance 10
configure wave -datasetprefix 0
configure wave -rowmargin 4
configure wave -childrowmargin 2
configure wave -gridoffset 0
configure wave -gridperiod 1
configure wave -griddelta 40
configure wave -timeline 0
configure wave -timelineunits ps
update
