@echo off
rem ============================================================================
rem BD32 GDB 在线调试一键测试
rem 前置：板子已连接 JTAG（FT2232H）且已烧入含 Trigger 修复的 bitstream
rem 用法：本机 exec 环境 Winsock 损坏，需通过任务计划程序运行本脚本：
rem   schtasks /create /f /tn BD32_GDB /tr "%~f0" /sc once /st 23:59
rem   schtasks /run /tn BD32_GDB
rem 结果输出：logs/gdb_test_result.txt（OpenOCD 日志 logs/gdb_test_ocd.log）
rem ============================================================================
cd /d D:\Desktop\OpenClaw_Workspace
mkdir logs 2>nul
taskkill /f /im openocd.exe 2>nul
rem 预清理：DM 复位（dmactive 0->1）恢复 tdata1 复位值，
rem 避免上次会话清掉的 trigger 导致 hbreak 找不到可用资源
Working\SDK\tools\xpack-openocd-0.12.0-7\bin\openocd.exe -f Working\SDK\tools\bd32_openocd.cfg -c "init" -c "bd32.cpu riscv dmi_write 0x10 0x0" -c "bd32.cpu riscv dmi_write 0x10 0x1" -c "shutdown" >> logs\gdb_test_ocd.log 2>&1
ping -n 4 127.0.0.1 >nul
start /b "" Working\SDK\tools\xpack-openocd-0.12.0-7\bin\openocd.exe -f Working\SDK\tools\bd32_openocd.cfg > logs\gdb_test_ocd.log 2>&1
ping -n 8 127.0.0.1 >nul
"D:\NucleiStudio\toolchain\gcc\bin\riscv64-unknown-elf-gdb.exe" -batch -x Working\SDK\tools\bd32_debug_test.gdb > logs\gdb_test_result.txt 2>&1
taskkill /f /im openocd.exe >> logs\gdb_test_result.txt 2>&1
echo done. result: logs\gdb_test_result.txt
