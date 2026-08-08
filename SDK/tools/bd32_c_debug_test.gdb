# =============================================================================
# BD32 GDB C 语言级在线调试测试（管道模式，无需 socket）
# 前置：
#   - 板子已烧录含 tdata1 修复（type=0 写入 -> 0x20000000）的 bitstream，
#     否则多次 next 会耗尽 4 路硬件触发
#   - breathing.elf 以 --debug 构建（run_gdb_c_debug.bat 会自动构建）
# 验证：
#   1) hbreak main + continue（全速运行到 C 函数入口）
#   2) 源码行信息（info line / list，确认 -g 调试信息）
#   3) next 连续 C 行单步（依赖触发槽可复用）
#   4) 查看局部变量（print ccr / dir / info locals）
# 运行：run_gdb_c_debug.bat
# =============================================================================
set pagination off
set confirm off
set architecture riscv:rv32
set breakpoint auto-hw on
file SDK/demos/nolibc/breathing/build/breathing.elf
target extended-remote | SDK/tools/xpack-openocd-0.12.0-7/bin/openocd.exe -c "gdb port pipe" -c "log_output logs/gdb_c_debug_ocd.log" -c "telnet port disabled" -c "tcl port disabled" -f SDK/tools/bd32_openocd.cfg

monitor reset halt
flushregs
p/x $pc
load
set $pc = 0x10000
flushregs

printf "\n==== [1] hbreak main + continue ====\n"
hbreak main
continue
flushregs
p/x $pc

printf "\n==== [2] source line info ====\n"
info line main
list 30, 58

printf "\n==== [3] C-level next x18 ====\n"
next
next
next
next
next
next
next
next
next
next
next
next
next
next
next
next
next
next
flushregs
p/x $pc

printf "\n==== [4] locals ====\n"
info locals
print ccr
print dir

printf "\n==== [5] software breakpoint (break, auto-hw off) ====\n"
set breakpoint auto-hw off
delete breakpoints
monitor reset halt
flushregs
set $pc = 0x10000
flushregs
break delay_ms
continue
flushregs
p/x $pc
stepi
flushregs
p/x $pc
info breakpoints
delete breakpoints
set breakpoint auto-hw on

printf "\n==== [6] cleanup ====\n"
detach
quit
