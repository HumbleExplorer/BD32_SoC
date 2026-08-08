@echo off
rem ============================================================================
rem BD32 GDB watchpoint on-board test (pipe mode, no socket needed)
rem Result: logs\gdb_watchpoint_result.txt, OpenOCD log: logs\gdb_watchpoint_ocd.log
rem ============================================================================
cd /d %~dp0..\..
if not defined RISCV_GDB set RISCV_GDB=D:\RISCV_Tool\xpack-riscv-none-elf-gcc-15.2.0-1\bin\riscv-none-elf-gdb.exe

mkdir logs 2>nul
taskkill /f /im openocd.exe 2>nul
"%RISCV_GDB%" -batch -x SDK\tools\bd32_watchpoint_test.gdb > logs\gdb_watchpoint_result.txt 2>&1
echo done. result: logs\gdb_watchpoint_result.txt
