@echo off
rem ============================================================================
rem BD32 peripheral ModelSim regression (tb_apb_uart / tb_apb_gpio /
rem tb_apb_plic / tb_apb_timer), headless -batch mode.
rem Output: logs/uart_test_out.txt, gpio_test_out.txt, plic_test_out.txt,
rem          timer_test_out.txt
rem Env: MODELSIM_PATH (default D:\modeltech64_2020.4\win64), MGLS_LICENSE_FILE
rem ============================================================================
@setlocal
set REPO=%~dp0..
if not defined MODELSIM_PATH set MODELSIM_PATH=D:\modeltech64_2020.4\win64
if not defined MGLS_LICENSE_FILE set MGLS_LICENSE_FILE=%MODELSIM_PATH%\..\LICENSE.TXT
set LOGS=%REPO%\logs
mkdir "%LOGS%" 2>nul

cd /d "%REPO%\script\uart_test"
"%MODELSIM_PATH%\vsim.exe" -batch -do "do run.do; quit -f" > "%LOGS%\uart_test_out.txt" 2>&1
echo uart-exit-%errorlevel% >> "%LOGS%\periph_mark.txt"

cd /d "%REPO%\script\gpio_test"
"%MODELSIM_PATH%\vsim.exe" -batch -do "do run.do; quit -f" > "%LOGS%\gpio_test_out.txt" 2>&1
echo gpio-exit-%errorlevel% >> "%LOGS%\periph_mark.txt"

cd /d "%REPO%\script\plic_test"
"%MODELSIM_PATH%\vsim.exe" -batch -do "do run.do; quit -f" > "%LOGS%\plic_test_out.txt" 2>&1
echo plic-exit-%errorlevel% >> "%LOGS%\periph_mark.txt"

cd /d "%REPO%\script\timer_test"
"%MODELSIM_PATH%\vsim.exe" -batch -do "do run.do; quit -f" > "%LOGS%\timer_test_out.txt" 2>&1
echo timer-exit-%errorlevel% >> "%LOGS%\periph_mark.txt"

@endlocal
