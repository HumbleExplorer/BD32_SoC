@echo off
REM =====================================================
REM BD32_SoC C 程序编译脚本
REM 将 C 源码 + start.s 编译为可直接下载的 .uartbin 文件
REM =====================================================

set SRC_DIR=..\src
set LIB_DIR=..\lib
set OUT_DIR=..\test_data\custom
set PROG=minimal

echo.
echo Compiling %PROG% ...
echo.

REM 1. 编译 C 源码 + tinyprintf + 链接启动代码
riscv64-unknown-elf-gcc ^
    -march=rv32im -mabi=ilp32 -nostartfiles -nostdlib -ffreestanding -Os ^
    -I %SRC_DIR% -I %LIB_DIR% ^
    -T %LIB_DIR%\link.ld ^
    -o %OUT_DIR%\%PROG%.elf ^
    %LIB_DIR%\start.s ^
    %LIB_DIR%\tinyprintf.c ^
    %SRC_DIR%\main.c
if %ERRORLEVEL% neq 0 goto err

REM 2. 生成 UART 下载二进制文件（包含帧头，可直接发送）
python "%~dp0elf2uartbin.py" ^
    %OUT_DIR%\%PROG%.elf ^
    %OUT_DIR%\%PROG%.uartbin
if %ERRORLEVEL% neq 0 goto err

REM 3. 反汇编输出，方便调试
riscv64-unknown-elf-objdump -d ^
    %OUT_DIR%\%PROG%.elf ^
    > %OUT_DIR%\%PROG%.dump

echo.
echo ========================================
echo  Done!
echo  UART Bin: %OUT_DIR%\%PROG%.uartbin
echo  Dump:     %OUT_DIR%\%PROG%.dump
echo ========================================
echo.
echo  上板下载: 直接通过串口发送 %PROG%.uartbin（含帧头）
echo.
echo  仿真: tb_soc_top 自动读取 .uartbin 二进制文件
echo.
goto end

:err
echo.
echo Build Failed!
pause
:end
