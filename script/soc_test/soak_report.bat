@echo off
cd /d D:\Desktop\OpenClaw_Workspace\RISCV_CPU\Working\script\soc_test
powershell -Command "Get-CimInstance Win32_Process -Filter \"Name='python.exe'\" | Where-Object {$_.CommandLine -like '*soak_uart_listener*'} | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }"
python soak_report.py
