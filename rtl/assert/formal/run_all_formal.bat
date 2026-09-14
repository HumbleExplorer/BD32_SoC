@echo off
rem ============================================================================
rem BD32 形式验证一键全跑（SymbiYosys）：OITF / Mem_Access / AXI_Lite_Master / IFU_Buffer
rem 每个模块 bmc + prove(abc pdr 无界) + cover 三任务。
rem 用法：双击或在任意 shell 调用；输出见各 *_formal_<task>\logfile.txt
rem 注意：sby_core.py 已打 GBK decode 补丁（OSS CAD Suite 升级后需重打，
rem       见 doc/property_plan_oitf.md "Windows 运行环境坑"）
rem ============================================================================
call D:\IC_Design_Toolkit\oss-cad-suite\environment.bat
cd /d %~dp0

set FAILED=0
for %%m in (oitf_formal mem_access_formal axi_master_formal ifu_buffer_formal) do (
  echo ============ %%m ============
  sby -f %%m.sby
  if errorlevel 1 set FAILED=1
)

if %FAILED%==1 (
  echo ============ FORMAL: FAIL ============
  exit /b 1
)
echo ============ FORMAL: ALL PASS ============
exit /b 0
