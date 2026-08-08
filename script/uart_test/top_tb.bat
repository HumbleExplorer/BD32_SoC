if defined MODELSIM_PATH ("%MODELSIM_PATH%\modelsim" -do run.do) else (modelsim -do run.do)

:clean_workspace

rmdir /S /Q work
del vsim.wlf
del *.vstf
del *.vcd
del *.ini
del transcript

:end