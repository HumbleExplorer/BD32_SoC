# ============================================================
# 总线访问超时测试 — 纯功能验证（无波形日志，跑得快）
# 用法: <ModelSim 安装目录>\win64\vsim -c -do run_bus_timeout_fast.do
# ============================================================

if [file exists "work"] {vdel -all}
vlib work
vmap work work

vlog +define+BUS_TIMEOUT_TEST -f filelist.f

# 与 reset 测试一致用 -voptargs=+acc；不 add wave → 不写 WLF
vsim -voptargs=+acc tb_soc_top
set NoQuitOnFinish 1
onbreak {resume}

run 300ms
echo "=== SIMULATION TIME REACHED 300ms ==="
quit -f
