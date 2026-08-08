@echo off
rem ============================================================================
rem BD32 software-breakpoint continue on-board regression (GDB pipe mode)
rem Prereq: bitstream with Debug Module; RV-Debugger (FT2232H) in WinUSB mode
rem Scenarios: S1 direct continue from sw bp hit (main -> uart_puts)
rem            S2 stepi past sw bp then continue (uart_init -> uart_puts)
rem            S3 direct continue from hw bp hit (main -> uart_puts)
rem Result: logs\gdb_swbp_continue_result.txt
rem ============================================================================
cd /d %~dp0..\..
if not defined RISCV_GDB set RISCV_GDB=D:\RISCV_Tool\xpack-riscv-none-elf-gcc-15.2.0-1\bin\riscv-none-elf-gdb.exe
mkdir logs 2>nul
taskkill /f /im openocd.exe 2>nul
"%RISCV_GDB%" -batch -x SDK\tools\bd32_swbp_continue_test.gdb > logs\gdb_swbp_continue_result.txt 2>&1
echo done. result: logs\gdb_swbp_continue_result.txt
