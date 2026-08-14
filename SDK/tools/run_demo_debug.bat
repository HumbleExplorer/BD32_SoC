@echo off
cd /d %~dp0..\..
if not defined RISCV_GDB set RISCV_GDB=D:\RISCV_Tool\xpack-riscv-none-elf-gcc-15.2.0-1\bin\riscv-none-elf-gdb.exe

mkdir logs 2>nul
taskkill /f /im openocd.exe 2>nul
start /b "" third_party\xpack-openocd-0.12.0-7\bin\openocd.exe -f SDK\tools\bd32_openocd.cfg > logs\demo_debug_ocd.log 2>&1
ping -n 8 127.0.0.1 >nul
"%RISCV_GDB%" -batch -x SDK\tools\bd32_demo_debug.gdb > logs\demo_debug_result.txt 2>&1
taskkill /f /im openocd.exe >> logs\demo_debug_result.txt 2>&1
echo done >> logs\demo_debug_result.txt
