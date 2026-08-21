@echo off
rem ============================================================================
rem BD32 RT-Thread lts-v3.1.x + picolibc demo SoC simulation (tb_soc_top, DIRECT_LOAD)
rem Run from script/soc_test so ../../test_data relative paths resolve.
rem Loads rtthread_picolibc_os_itcm.mem / rtthread_picolibc_os_dtcm.mem (build with
rem   python tools/build.py demos/rtthread --rtthread --picolibc)
rem Output: logs/rtthread_sim315_pico_out.txt (UART prints t1/t2 alternately)
rem ============================================================================
@setlocal
set REPO=%~dp0..\..
if not defined MODELSIM_PATH set MODELSIM_PATH=D:\modeltech64_2020.4\win64
if not defined MGLS_LICENSE_FILE set MGLS_LICENSE_FILE=%MODELSIM_PATH%\..\LICENSE.TXT
set LOGS=%REPO%\logs
mkdir "%LOGS%" 2>nul
cd /d "%~dp0"
echo vlog-start >> "%LOGS%\rtthread_sim315_pico_mark.txt"
"%MODELSIM_PATH%\vsim.exe" -batch -do "do rtthread_sim315_pico.do" > "%LOGS%\rtthread_sim315_pico_out.txt" 2>&1
echo vsim-exit-%errorlevel% >> "%LOGS%\rtthread_sim315_pico_mark.txt"
echo done: logs\rtthread_sim315_pico_out.txt
@endlocal
