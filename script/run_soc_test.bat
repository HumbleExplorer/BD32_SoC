@echo off
rem ============================================================================
rem BD32 SoC ModelSim test (tb_soc_top, CoreMark boot phase), headless -batch.
rem Output: logs/soc_test_out.txt
rem Env: MODELSIM_PATH (default D:\modeltech64_2020.4\win64), MGLS_LICENSE_FILE
rem ============================================================================
@setlocal
set REPO=%~dp0..
if not defined MODELSIM_PATH set MODELSIM_PATH=D:\modeltech64_2020.4\win64
if not defined MGLS_LICENSE_FILE set MGLS_LICENSE_FILE=%MODELSIM_PATH%\..\LICENSE.TXT
set LOGS=%REPO%\logs
mkdir "%LOGS%" 2>nul

cd /d "%REPO%\script\soc_test"
"%MODELSIM_PATH%\vsim.exe" -batch -do "do run.do; quit -f" > "%LOGS%\soc_test_out.txt" 2>&1
echo soc-exit-%errorlevel% > "%LOGS%\soc_mark.txt"

@endlocal
