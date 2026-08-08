set pagination off
set confirm off
set architecture riscv:rv32
file SDK/demos/nolibc/breathing/build/breathing.elf
target extended-remote :3333

printf "\n==== [0] DM 复位 + reset halt ====\n"
monitor bd32.cpu riscv dmi_write 0x10 0x0
monitor bd32.cpu riscv dmi_write 0x10 0x1
monitor reset halt
flushregs
p/x $pc

printf "\n==== [1] load breathing.elf ====\n"
load
flushregs

printf "\n==== [2] $pc=0x10000，hbreak main，continue ====\n"
set $pc = 0x10000
flushregs
hbreak main
continue
flushregs
p/x $pc
info breakpoints

printf "\n==== [3] 删除断点后单步 4 条（依赖 trigger halt 锁存）====\n"
delete breakpoints
stepi
flushregs
p/x $pc
stepi
flushregs
p/x $pc
stepi
flushregs
p/x $pc
stepi
flushregs
p/x $pc
info registers

printf "\n==== [4] 全局变量 / .data / mtime ====\n"
p/x *(unsigned int*)0x20130
x/4wx 0x20000
p/x $time

printf "\n==== [5] 清理 ====\n"
detach
quit
