# ============================================================
# 总线访问超时测试 — 纯功能验证（无波形日志，跑得快）
# 用法: <ModelSim 安装目录>\win64\vsim -c -do run_bus_timeout_fast.do
# ============================================================

if {[file exists "../../build/msim/run_bus_timeout_fast/work"]} {file delete -force "../../build/msim/run_bus_timeout_fast/work"}
file mkdir ../../build/msim/run_bus_timeout_fast
vlib ../../build/msim/run_bus_timeout_fast/work
vmap work ../../build/msim/run_bus_timeout_fast/work

vlog +define+BUS_TIMEOUT_TEST -f filelist.f

# 与 reset 测试一致用 -voptargs=+acc；不 add wave → 不写 WLF
vsim -voptargs=+acc tb_soc_top
set NoQuitOnFinish 1
onbreak {resume}

# 下载 ~270.5ms + 判定窗口 30ms ≈ 310ms，留余量 400ms
run 400ms
echo "=== SIMULATION TIME REACHED 300ms ==="
quit -f
