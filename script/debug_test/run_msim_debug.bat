@echo off
rem ============================================================================
rem BD32 Debug ModelSim 回归一键测试（tb_debug，31 项断言）
rem 本脚本位于 script/debug_test（验证脚本目录）；SDK/ 仅放软件运行相关工具
rem 用法：本机 exec 环境 Winsock 损坏，需通过任务计划程序运行本脚本：
rem   schtasks /create /f /tn BD32_MSIM /tr "%~f0" /sc once /st 23:59
rem   schtasks /run /tn BD32_MSIM
rem 结果输出：logs/msim_out.txt（进度标记 logs/msim_mark.txt）
rem ============================================================================
mkdir D:\Desktop\OpenClaw_Workspace\logs 2>nul
echo bat-started > D:\Desktop\OpenClaw_Workspace\logs\msim_mark.txt
echo cwd0=%CD% >> D:\Desktop\OpenClaw_Workspace\logs\msim_mark.txt
set MGLS_LICENSE_FILE=D:\modeltech64_2020.4\LICENSE.TXT
cd /d D:\Desktop\OpenClaw_Workspace\Working\sim
echo cwd1=%CD% >> D:\Desktop\OpenClaw_Workspace\logs\msim_mark.txt
D:\modeltech64_2020.4\win64\vsim.exe -c -do "do {D:/Desktop/OpenClaw_Workspace/Working/sim/_run_all.do}; quit -f" > D:\Desktop\OpenClaw_Workspace\logs\msim_out.txt 2>&1
echo vsim-exit-%errorlevel% >> D:\Desktop\OpenClaw_Workspace\logs\msim_mark.txt
