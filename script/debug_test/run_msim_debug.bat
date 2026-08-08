@echo off
rem ============================================================================
rem BD32 Debug ModelSim regression (tb_debug)
rem Lives in script/debug_test (verification dir); SDK/ is for SW run tools
rem Headless -batch mode (no socket server), run from script/debug_test so
rem that ../../test_data relative paths in SoC_Config.sv resolve correctly.
rem Output: logs/msim_out.txt (progress marker logs/msim_mark.txt)
rem Env: MODELSIM_PATH (default D:\modeltech64_2020.4\win64), MGLS_LICENSE_FILE
rem ============================================================================
@setlocal
set REPO=%~dp0..\..
if not defined MODELSIM_PATH set MODELSIM_PATH=D:\modeltech64_2020.4\win64
if not defined MGLS_LICENSE_FILE set MGLS_LICENSE_FILE=%MODELSIM_PATH%\..\LICENSE.TXT
set LOGS=%REPO%\logs
set DO=%REPO:\=/%
mkdir "%LOGS%" 2>nul
echo bat-started > "%LOGS%\msim_mark.txt"
echo cwd0=%CD% >> "%LOGS%\msim_mark.txt"
cd /d "%REPO%\script\debug_test"
echo cwd1=%CD% >> "%LOGS%\msim_mark.txt"
"%MODELSIM_PATH%\vsim.exe" -batch -do "do {%DO%/script/debug_test/run_msim_debug.do}; quit -f" > "%LOGS%\msim_out.txt" 2>&1
echo vsim-exit-%errorlevel% >> "%LOGS%\msim_mark.txt"
@endlocal
