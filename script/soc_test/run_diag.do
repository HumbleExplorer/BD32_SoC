# 诊断：跑 25ms，观察 MROM 启动是否越过测频循环并进入 download_mode
if {[file exists "../../build/msim/run_diag/work"]} {file delete -force "../../build/msim/run_diag/work"}
file mkdir ../../build/msim/run_diag
vlib ../../build/msim/run_diag/work
vmap work ../../build/msim/run_diag/work
vlog +define+BUS_TIMEOUT_TEST -f filelist.f
vsim tb_soc_top
set NoQuitOnFinish 1
onbreak {resume}
run 16ms
echo "=== DIAG DONE ==="
quit -f
