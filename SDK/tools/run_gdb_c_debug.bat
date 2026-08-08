@echo off
rem ============================================================================
rem BD32 GDB C-level on-line debug test (pipe mode, no socket needed)
rem Prereq: bitstream with tdata1 fix (type=0 write -> 0x20000000) so that
rem         multiple 'next' can reuse the 4 hardware triggers
rem This script rebuilds breathing.elf with --debug --opt O0 first
rem (-g debug info + -O0 so GDB can read local variables reliably).
rem Result: logs\gdb_c_debug_result.txt, OpenOCD log logs\gdb_c_debug_ocd.log
rem ============================================================================
cd /d %~dp0..\..
if not defined RISCV_GDB set RISCV_GDB=D:\RISCV_Tool\xpack-riscv-none-elf-gcc-15.2.0-1\bin\riscv-none-elf-gdb.exe
mkdir logs 2>nul
taskkill /f /im openocd.exe 2>nul
echo [build] rebuilding breathing with --debug ...
python SDK\tools\build.py SDK\demos\nolibc\breathing -o SDK\demos\nolibc\breathing\build\breathing.elf --debug --opt O0
"%RISCV_GDB%" -batch -x SDK\tools\bd32_c_debug_test.gdb > logs\gdb_c_debug_result.txt 2>&1
echo done. result: logs\gdb_c_debug_result.txt
