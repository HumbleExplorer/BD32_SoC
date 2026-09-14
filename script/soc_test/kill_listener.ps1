Get-CimInstance Win32_Process -Filter "Name='python.exe'" | Where-Object {
    $_.CommandLine -like '*soak_uart_listener*'
} | ForEach-Object {
    Write-Host ("killing " + $_.ProcessId)
    Stop-Process -Id $_.ProcessId -Force
}
