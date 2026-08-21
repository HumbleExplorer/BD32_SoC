@echo off
rem ============================================================================
rem BD32 full simulation regression (headless ModelSim, about 1-1.5 h)
rem   1. custom_asm core regression     (38, script/run_all_custom_asm.py)
rem   2. riscv-tests core regression    (50, script/run_all_riscv_tests.py)
rem   3. debug module regression        (94, script/debug_test/run_msim_debug.bat)
rem   4. peripheral regression          (UART/GPIO/PLIC/Timer)
rem   5. soc smoke test
rem   6. rt-thread sims                 (lts-v3.1.x / v5.1.0 x newlib / picolibc)
rem Progress/exit codes: logs\verify_all_mark.txt
rem ============================================================================
@setlocal
set PY=D:\Python312\python.exe
set REPO=%~dp0..
set LOGS=%REPO%\logs
mkdir "%LOGS%" 2>nul
echo verify-all started %date% %time% > "%LOGS%\verify_all_mark.txt"

echo [1/6] custom_asm (38) ...
cd /d "%REPO%\script"
"%PY%" run_all_custom_asm.py
echo custom_asm-exit-%errorlevel% >> "%LOGS%\verify_all_mark.txt"

echo [2/6] riscv-tests (50) ...
"%PY%" run_all_riscv_tests.py
echo riscv_tests-exit-%errorlevel% >> "%LOGS%\verify_all_mark.txt"

echo [3/6] debug (94) ...
call "%REPO%\script\debug_test\run_msim_debug.bat"
echo debug-exit-%errorlevel% >> "%LOGS%\verify_all_mark.txt"

echo [4/6] peripherals ...
call "%REPO%\script\run_periph_regression.bat"
echo periph-exit-%errorlevel% >> "%LOGS%\verify_all_mark.txt"

echo [5/6] soc smoke ...
call "%REPO%\script\run_soc_test.bat"
echo soc-exit-%errorlevel% >> "%LOGS%\verify_all_mark.txt"

echo [6/6] rt-thread sims ...
call "%REPO%\script\soc_test\run_rtthread_sim.bat"
echo rtthread315-exit-%errorlevel% >> "%LOGS%\verify_all_mark.txt"
call "%REPO%\script\soc_test\run_rtthread_sim315_pico.bat"
echo rtthread315_pico-exit-%errorlevel% >> "%LOGS%\verify_all_mark.txt"
call "%REPO%\script\soc_test\run_rtthread_sim51.bat"
echo rtthread51-exit-%errorlevel% >> "%LOGS%\verify_all_mark.txt"
call "%REPO%\script\soc_test\run_rtthread_sim51_pico.bat"
echo rtthread51_pico-exit-%errorlevel% >> "%LOGS%\verify_all_mark.txt"

echo verify-all done %date% %time% >> "%LOGS%\verify_all_mark.txt"
echo.
echo ==================== progress / exit codes ====================
type "%LOGS%\verify_all_mark.txt"
echo.
echo Details are in logs\. Close this window when done.
pause
@endlocal
