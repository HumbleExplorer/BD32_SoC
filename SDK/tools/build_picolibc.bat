@echo off
REM ============================================================
REM BD32 picolibc one-click build
REM
REM meson needs asyncio/Winsock, which cannot start in the
REM sandbox exec environment. Run this in a normal cmd session
REM (double-click works) or via Task Scheduler.
REM
REM Usage: build_picolibc.bat [i|f|d]
REM   i = integer printf (default, smallest)
REM   f = float printf
REM   d = double printf
REM
REM Output: third_party/picolibc-install/ (i)
REM         third_party/picolibc-install-<f|d>/ (f/d)
REM            include/
REM            lib/rv32im/ilp32/
REM ============================================================
setlocal

set "TOOLS=%~dp0"
set "VARIANT=%~1"
if "%VARIANT%"=="" set "VARIANT=i"
if not "%VARIANT%"=="i" if not "%VARIANT%"=="f" if not "%VARIANT%"=="d" (
  echo [ERROR] invalid variant: %VARIANT% ^(use i, f or d^)
  exit /b 1
)

for %%I in ("%TOOLS%..\..\third_party\picolibc-1.8.12") do set "SRC=%%~fI"
if "%VARIANT%"=="i" (
  for %%I in ("%TOOLS%..\..\third_party\picolibc-install") do set "PREFIX=%%~fI"
) else (
  for %%I in ("%TOOLS%..\..\third_party\picolibc-install-%VARIANT%") do set "PREFIX=%%~fI"
)
set "BUILD=%SRC%\build-bd32"
set "CROSS=%TOOLS%picolibc-cross-rv32im.txt"
set "TOOLCHAIN=D:\RISCV_Tool\xpack-riscv-none-elf-gcc-15.2.0-1\bin"

if not exist "%SRC%\meson.build" (
  echo [ERROR] picolibc source not found: %SRC%
  exit /b 1
)
if not exist "%TOOLCHAIN%\riscv-none-elf-gcc.exe" (
  echo [ERROR] toolchain not found: %TOOLCHAIN%
  exit /b 1
)

REM Cross builds validate --prefix with POSIX path semantics, so a
REM Windows path like D:\... is rejected as not absolute. Convert
REM prefix to drive-root-relative POSIX form (/Desktop/...) and cd
REM to the drive of this script first.
cd /d %~d0\
set "POSIX_PREFIX=/%PREFIX:~3%"
set "POSIX_PREFIX=%POSIX_PREFIX:\=/%"

set "PATH=%TOOLCHAIN%;%PATH%"

where meson >nul 2>&1
if errorlevel 1 (
  echo [ERROR] meson not found. Install with: pip install meson
  exit /b 1
)
where ninja >nul 2>&1
if errorlevel 1 (
  echo [ERROR] ninja not found. Install with: pip install ninja
  exit /b 1
)

echo [1/3] meson setup ...
if exist "%BUILD%" rmdir /s /q "%BUILD%"
meson setup "%BUILD%" "%SRC%" --cross-file "%CROSS%" ^
  -Dmultilib-list=rv32im/ilp32 --prefix "%POSIX_PREFIX%" ^
  -Dspecsdir=none -Dincludedir=include -Dlibdir=lib ^
  -Dtests=false -Dsemihost=false -Dpicocrt=false ^
  -Dformat-default=%VARIANT%
if errorlevel 1 goto :fail

echo [2/3] ninja build ...
ninja -C "%BUILD%"
if errorlevel 1 goto :fail

echo [3/3] install ...
meson install -C "%BUILD%"
if errorlevel 1 goto :fail

echo.
echo picolibc (%VARIANT%) installed to: %PREFIX%
echo headers : %PREFIX%\include
echo libs    : %PREFIX%\lib\rv32im\ilp32
exit /b 0

:fail
echo.
echo [ERROR] picolibc build failed, see messages above.
exit /b 1
