@echo off
rem ============================================================================
rem BD32 watchpoint 上板测试（OpenOCD TCL 批处理，�?socket�?rem 前置：板子已烧录�?watchpoint �?bitstream，JTAG 已连�?rem �?exec 环境 Winsock 损坏，通过计划任务运行�?rem   schtasks /create /f /tn BD32_WP /tr "%~f0" /sc once /st 23:59
rem   schtasks /run /tn BD32_WP
rem 结果输出：logs/watchpoint_test.log
rem ============================================================================
cd /d %~dp0..\..
mkdir logs 2>nul
taskkill /f /im openocd.exe 2>nul
third_party\xpack-openocd-0.12.0-7\bin\openocd.exe -f SDK\tools\bd32_watchpoint_test.cfg > logs\watchpoint_test.log 2>&1
echo done. result: logs\watchpoint_test.log
