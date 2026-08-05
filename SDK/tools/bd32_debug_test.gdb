set pagination off
set confirm off
set architecture riscv:rv32
target extended-remote :3333

printf "\n==== [1] reset halt ====\n"
monitor reset halt
flushregs

printf "\n==== [2] halt + PC ====\n"
monitor halt
flushregs
p/x $pc

printf "\n==== [3] GPR 读 ====\n"
info registers

printf "\n==== [4] CSR 读 ====\n"
p/x $mstatus
p/x $mtvec
p/x $dcsr
p/x $dpc

printf "\n==== [5] 单步 x3（预期 PC 每步 +4）====\n"
stepi
flushregs
p/x $pc
stepi
flushregs
p/x $pc
stepi
flushregs
p/x $pc

printf "\n==== [6] GPR 写/读回 a0=0x12345678 ====\n"
set $a0 = 0x12345678
p/x $a0

printf "\n==== [7] resume 后 halt ====\n"
monitor resume
shell ping -n 2 127.0.0.1 >nul
monitor halt
flushregs
p/x $pc

printf "\n==== [8] 内存读 ITCM 0x10000 ====\n"
x/4wx 0x10000

printf "\n==== [9] 内存写读 DTCM 0x20000000 ====\n"
set {int}0x20000000 = 0xdeadbeef
x/1wx 0x20000000

printf "\n==== [10] Trigger 硬件断点（NOP 滑道 0x10200 -> 命中 0x10204）====\n"
set {int}0x10200 = 0x00000013
set {int}0x10204 = 0x00000013
set {int}0x10208 = 0x00000013
set {int}0x1020c = 0x00000013
set $pc = 0x10200
flushregs
hbreak *0x10204
continue
flushregs
p/x $pc
info breakpoints
delete breakpoints

printf "\n==== [11] 清理 ====\n"
set $a0 = 0
detach
quit
