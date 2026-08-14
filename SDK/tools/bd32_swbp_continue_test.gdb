# =============================================================================
# BD32 软件断点 continue 上板回归测试（管道模式，无需 socket）
# 场景 1：直接 continue（PC 停在软件断点地址，断点仍插入）
#   break main（只执行一次） + break uart_puts（main 内紧随其后，只执行一次）
#   命中 main 后直接 continue，若恢复正确应停在 uart_puts 而非重新命中 main
# 场景 2：stepi 越过软件断点后 continue
#   break uart_init（启动代码调用一次） -> stepi -> 删除断点 -> hbreak uart_puts
#   继续运行应停在 uart_puts，证明 resume 从 stepi 后的 PC 正常继续
# 结果：logs\gdb_swbp_continue_result.txt
# =============================================================================
set pagination off
set confirm off
set architecture riscv:rv32
set breakpoint auto-hw off
file SDK/demos/nolibc/breathing/build/breathing.elf
target extended-remote | third_party/xpack-openocd-0.12.0-7/bin/openocd.exe -c "gdb port pipe" -c "log_output logs/swbp_continue_ocd.log" -c "telnet port disabled" -c "tcl port disabled" -f SDK/tools/bd32_openocd.cfg

printf "\n==== S1: 软件断点直接 continue ====\n"
monitor reset halt
load
set $pc = 0x10000
flushregs

break main
break uart_puts
info breakpoints
continue
flushregs
printf "S1 命中1: pc="
p/x $pc
printf "S1 main 处内存（应为 ebreak 0x00100073）: "
x/1wx main
printf "S1 ra="
p/x $ra
printf "S1 sp="
p/x $sp

printf "\nS1 直接 continue（PC==断点地址，断点仍插入）...\n"
continue
flushregs
printf "S1 命中2: pc="
p/x $pc
printf "S1 ra="
p/x $ra
printf "S1 sp="
p/x $sp

printf "\n==== S2: stepi 越过软件断点后 continue ====\n"
delete breakpoints
monitor reset halt
load
set $pc = 0x10000
flushregs

break uart_init
continue
flushregs
printf "S2 命中1: pc="
p/x $pc

stepi
flushregs
printf "S2 stepi 后 pc="
p/x $pc

delete breakpoints
hbreak uart_puts
continue
flushregs
printf "S2 命中2: pc="
p/x $pc

printf "\n==== S3: 硬件断点直接 continue（trigger 重插后应越过）====\n"
delete breakpoints
monitor reset halt
load
set $pc = 0x10000
flushregs

hbreak main
hbreak uart_puts
continue
flushregs
printf "S3 命中1: pc="
p/x $pc

printf "\nS3 直接 continue（PC==硬件断点地址，trigger 仍使能）...\n"
continue
flushregs
printf "S3 命中2: pc="
p/x $pc

printf "\n==== S4: hw bp 命中 -> reset halt -> 重新 hbreak -> continue ====\n"
# Regression for the OpenOCD watchpoint-dance bug: after a trigger hit
# debug_reason stays WATCHPOINT through reset halt; the next continue
# disables triggers, steps one instruction (at 0x10000: `j _start`) and
# resumes. Without the STEP_DRAIN branch fix the step lands at 0x10004
# (a gap) and the CPU runs away; with the fix it lands at 0x10100.
delete breakpoints
monitor reset halt
load
set $pc = 0x10000
flushregs
hbreak uart_puts
continue
flushregs
printf "S4 命中1: pc="
p/x $pc
delete breakpoints

monitor reset halt
load
set $pc = 0x10000
flushregs
hbreak main
hbreak uart_puts
continue
flushregs
printf "S4 命中2: pc="
p/x $pc
delete breakpoints

printf "\n==== S5: 软断点命中 -> reset halt -> 硬件断点命中 continue ====\n"
# Software breakpoint then hardware breakpoint combined: sw ebreak hit,
# reset halt, then hw trigger continue (sw+hw mix in one debug session).
monitor reset halt
load
set $pc = 0x10000
flushregs
break main
continue
flushregs
printf "S5 命中1(sw): pc="
p/x $pc
delete breakpoints

monitor reset halt
load
set $pc = 0x10000
flushregs
hbreak uart_puts
continue
flushregs
printf "S5 命中2(hw): pc="
p/x $pc
delete breakpoints

printf "\n==== 清理 ====\n"
delete breakpoints
detach
quit
