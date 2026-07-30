# =============================================================================
# pblock_cpu.tcl — CPU 核心 Pblock 物理约束
# 用途：将 CPU 核心（RISC_V_Core + Bus_Access）圈在连续区域中，
#       缩短 DTCM BRAM → CPU 内部逻辑的布线延迟
# 使用方法：在 Vivado Tcl Console 中 source 此文件（在 place_design 之前）
# 注意：不要在 XDC 中 include，Pblock 跟综合后的 cell 名强相关
# =============================================================================

# 创建 Pblock
if {[get_pblocks -quiet pblock_cpu] ne ""} {
    delete_pblocks pblock_cpu
}
create_pblock pblock_cpu

# 添加 CPU 核心
add_cells_to_pblock pblock_cpu [get_cells u_RISC_V_Core]

# 可选：把 Bus_Access 也拉近来（CPU 跟 Bus 交互密集）
# add_cells_to_pblock pblock_cpu [get_cells u_Bus_Access]

# 设定矩形区域
# xc7z020clg400 PL: 约 X0~X106, Y0~Y139
# 当前分布：BRAM 在 X_5Y15, 逻辑在 X60~X101Y50~Y80
resize_pblock pblock_cpu -add {SLICE_X60Y30:SLICE_X106Y80}
# BRAM 列的 X 坐标在 SLICE 坐标系中可能不同，需要留足余量
# resize_pblock pblock_cpu -add {SLICE_X55Y30:SLICE_X106Y85}

puts "INFO: Pblock pblock_cpu created for u_RISC_V_Core"
puts "INFO: Area: {SLICE_X60Y30:SLICE_X106Y80}"
