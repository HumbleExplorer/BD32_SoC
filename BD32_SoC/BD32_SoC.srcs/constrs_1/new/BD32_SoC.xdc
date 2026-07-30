create_clock -period 20.000 -name sys_clk [get_ports sys_clk]
set_property -dict {PACKAGE_PIN U18 IOSTANDARD LVCMOS33} [get_ports sys_clk]
set_property -dict {PACKAGE_PIN N16 IOSTANDARD LVCMOS33} [get_ports sys_rst_n]
set_property -dict {PACKAGE_PIN T19 IOSTANDARD LVCMOS33} [get_ports uart_rx]
set_property -dict {PACKAGE_PIN J15 IOSTANDARD LVCMOS33} [get_ports uart_tx]

# =====================================================================
# Sipeed RV-Debugger 接口引脚
# =====================================================================
# JTAG 引脚（预留，Debug Module 实现后启用）
set_property -dict {PACKAGE_PIN W11 IOSTANDARD LVCMOS33} [get_ports dbg_tck]
set_property -dict {PACKAGE_PIN U13 IOSTANDARD LVCMOS33} [get_ports dbg_tdo]
set_property -dict {PACKAGE_PIN U15 IOSTANDARD LVCMOS33} [get_ports dbg_tms]
set_property PACKAGE_PIN W13 [get_ports dbg_rst]
set_property IOSTANDARD LVCMOS33 [get_ports dbg_rst]
set_property PULLDOWN true [get_ports dbg_rst]
set_property -dict {PACKAGE_PIN Y14 IOSTANDARD LVCMOS33} [get_ports dbg_tdi]

# JTAG TCK 时钟约束（非时钟专用引脚，需允许普通路由）
create_clock -period 100.000 -name dbg_tck [get_ports dbg_tck]
set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets dbg_tck_IBUF]
# TCK ↔ sys_clk 异步域，不做跨域时序分析
set_false_path -from [get_clocks dbg_tck] -to [get_clocks clk_cpu_clk_wiz_0]
set_false_path -from [get_clocks clk_cpu_clk_wiz_0] -to [get_clocks dbg_tck]

# =====================================================================
# GPIO 引脚分配（5路）
# =====================================================================
# [0] MODE_SEL: W15 — 启动模式选择（输入，跳线帽接3.3V=正常启动，浮空=UART下载）
# [1] KEY0:     L14 — 按键0（输入）
# [2] KEY1:     K16 — 按键1（输入）
# [3] LED0:     H15 — 状态指示灯（输出）
# [4] LED2:     J16 — 状态指示灯（输出）
# =====================================================================
set_property -dict {PACKAGE_PIN W15 IOSTANDARD LVCMOS33} [get_ports {gpio_io[0]}]
set_property -dict {PACKAGE_PIN L14 IOSTANDARD LVCMOS33} [get_ports {gpio_io[1]}]
set_property -dict {PACKAGE_PIN K16 IOSTANDARD LVCMOS33} [get_ports {gpio_io[2]}]
set_property -dict {PACKAGE_PIN H15 IOSTANDARD LVCMOS33} [get_ports {gpio_io[3]}]
set_property -dict {PACKAGE_PIN J16 IOSTANDARD LVCMOS33} [get_ports {gpio_io[4]}]

# =====================================================================
# Timer 通道引脚分配（4路）
# =====================================================================
# [0] L15 — 呼吸灯 PWM 输出
# [1] T11 — 预留
# [2] T5  — 预留
# [3] U7  — 预留
set_property -dict {PACKAGE_PIN L15 IOSTANDARD LVCMOS33} [get_ports {timer_channel_io[0]}]
set_property -dict {PACKAGE_PIN T11 IOSTANDARD LVCMOS33} [get_ports {timer_channel_io[1]}]
set_property -dict {PACKAGE_PIN T5 IOSTANDARD LVCMOS33} [get_ports {timer_channel_io[2]}]
set_property -dict {PACKAGE_PIN U7 IOSTANDARD LVCMOS33} [get_ports {timer_channel_io[3]}]

# =====================================================================
# Pblock: RISC_V_Core + Bus 统一区域
# =====================================================================
# create_pblock pblock_u_RISC_V_Core_And_Bus
# add_cells_to_pblock [get_pblocks pblock_u_RISC_V_Core_And_Bus] [get_cells -quiet [list #           u_SoC_top/u_AXI_APB_Bridge #           u_SoC_top/u_AXI_Interconnect #           u_SoC_top/u_Bus_Access #           u_SoC_top/u_RISC_V_Core/u_BootROM #           u_SoC_top/u_RISC_V_Core/u_DTCM #           u_SoC_top/u_RISC_V_Core/u_DTCM_i_1 #           u_SoC_top/u_RISC_V_Core/u_Data_Hazard_Forward #           u_SoC_top/u_RISC_V_Core/u_Decoder #           u_SoC_top/u_RISC_V_Core/u_EX_MEM #           u_SoC_top/u_RISC_V_Core/u_ID_EX #           u_SoC_top/u_RISC_V_Core/u_IF_ID #           u_SoC_top/u_RISC_V_Core/u_MEM_WB #           u_SoC_top/u_RISC_V_Core/u_RegFile]]

# create_pblock pblock_PC_Predictor_ITCM
# add_cells_to_pblock [get_pblocks pblock_PC_Predictor_ITCM] [get_cells -quiet [list u_SoC_top/u_RISC_V_Core/u_Dynamic_Branch_Predictor u_SoC_top/u_RISC_V_Core/u_ITCM u_SoC_top/u_RISC_V_Core/u_PC_counter]]

# create_pblock pblock_CSR_Pipeline_Ctrl
# add_cells_to_pblock [get_pblocks pblock_CSR_Pipeline_Ctrl] [get_cells -quiet [list u_SoC_top/u_RISC_V_Core/u_CSR_Reg_Access u_SoC_top/u_RISC_V_Core/u_Pipeline_Ctrl]]

# create_pblock pblock_Executer_Mem_Access
# add_cells_to_pblock [get_pblocks pblock_Executer_Mem_Access] [get_cells -quiet [list u_SoC_top/u_RISC_V_Core/u_Executer u_SoC_top/u_RISC_V_Core/u_Mem_Access]]

# =====================================================================
# CDC 复位同步器路径设 false path（异步复位信号，不做 setup 分析）
# =====================================================================
set_false_path -from [get_cells u_cdc_rst_sync/*]
set_false_path -from [get_clocks sys_clk] -to [get_clocks clk_cpu_clk_wiz_0]
