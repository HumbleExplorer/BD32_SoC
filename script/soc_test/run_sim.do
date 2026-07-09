onbreak {resume}
onerror {resume}
quietly set NoQuitOnFinish 1
set NoQuitOnFinish 1

# 记录全部 SoC 内部信号到 vsim.wlf（供 GUI 打开 wave.do 检视 culprit store）
log -r /tb_soc_top/u_SoC_top/*

# 断点：抓"非对齐 store"（access_en & access_wr & addr[1:0]!=0）
# 命中即打印当前仿真时间 + 错误地址，便于在 wlf 中定位该时刻的 PC/操作数
when -label badstore {
  tb_soc_top.u_SoC_top.u_RISC_V_Core.u_Mem_Access.access_en == 1'b1 &&
  tb_soc_top.u_SoC_top.u_RISC_V_Core.u_Mem_Access.access_wr == 1'b1 &&
  tb_soc_top.u_SoC_top.u_RISC_V_Core.u_Mem_Access.access_addr[1:0] != 2'b00
} {
  puts "*** BAD STORE (misaligned) @ [now] : access_addr=[examine -hex tb_soc_top.u_SoC_top.u_RISC_V_Core.u_Mem_Access.access_addr]"
}

puts "=== batch simulation start (logging + bad-store watch) ==="
run 55ms
puts "=== batch simulation finished ==="
quit -f
