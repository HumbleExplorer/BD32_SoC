Get-CimInstance Win32_Process -Filter "Name='python.exe'" | ForEach-Object {
    Write-Host ("PID=" + $_.ProcessId + " CMD=" + $_.CommandLine)
}
Write-Host "---soak log tail---"
Get-Content "D:\Desktop\OpenClaw_Workspace\RISCV_CPU\Working\logs\soak_uart.log" -Tail 5
