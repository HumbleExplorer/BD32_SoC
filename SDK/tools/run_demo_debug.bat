@echo off
cd /d D:\Desktop\OpenClaw_Workspace
mkdir logs 2>nul
taskkill /f /im openocd.exe 2>nul
start /b "" Working\SDK\tools\xpack-openocd-0.12.0-7\bin\openocd.exe -f Working\SDK\tools\bd32_openocd.cfg > logs\demo_debug_ocd.log 2>&1
ping -n 8 127.0.0.1 >nul
"D:\NucleiStudio\toolchain\gcc\bin\riscv64-unknown-elf-gdb.exe" -batch -x Working\SDK\tools\bd32_demo_debug.gdb > logs\demo_debug_result.txt 2>&1
taskkill /f /im openocd.exe >> logs\demo_debug_result.txt 2>&1
echo done >> logs\demo_debug_result.txt
