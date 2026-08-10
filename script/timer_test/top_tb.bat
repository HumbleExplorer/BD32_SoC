@echo off
rem GUI 启动入口：依赖 run.do 第一行清理 work 库（file delete -force），
rem 其余临时文件由 cleanup_temp.py 统一清理。
if defined MODELSIM_PATH ("%MODELSIM_PATH%\modelsim" -do run.do) else (modelsim -do run.do)
