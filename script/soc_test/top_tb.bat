@echo off
rem BD32 SoC ModelSim GUI launcher.
rem run.do handles the work library cleanup; temp files are handled by cleanup_temp.py.
rem Always cd to this script's folder so "-do run.do" resolves correctly,
rem and keep this file ASCII-only (cmd uses the ANSI codepage to parse .bat).
cd /d "%~dp0"
if not defined MODELSIM_PATH set MODELSIM_PATH=D:\modeltech64_2020.4\win64
if not defined MGLS_LICENSE_FILE set MGLS_LICENSE_FILE=%MODELSIM_PATH%\..\LICENSE.TXT
"%MODELSIM_PATH%\modelsim.exe" -do run.do
if errorlevel 1 (
    echo.
    echo [ModelSim failed to start - please share the error above]
    pause
)
