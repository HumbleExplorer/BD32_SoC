# 对照实验：复位测试（无波形），看 MROM 是否能正常启动并置位 download_en
if [file exists "work"] {vdel -all}
vlib work
vmap work work

vlog +define+RESET_REDOWNLOAD_TEST -f filelist.f

vsim tb_soc_top
set NoQuitOnFinish 1
onbreak {resume}

# 只跑 60ms：若 MROM 正常，Phase1 下载会在几十 us 内开始
run 60ms
echo "=== CONTROL RESET TEST DONE (60ms) ==="
quit -f
