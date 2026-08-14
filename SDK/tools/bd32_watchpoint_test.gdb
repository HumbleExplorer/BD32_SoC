set pagination off
set confirm off
set architecture riscv:rv32
target extended-remote | third_party/xpack-openocd-0.12.0-7/bin/openocd.exe -c "gdb port pipe" -c "log_output logs/gdb_watchpoint_ocd.log" -c "telnet port disabled" -c "tcl port disabled" -f SDK/tools/bd32_openocd.cfg

printf "\n==== [0] reset halt ====\n"
monitor reset halt
flushregs
p/x $pc

printf "\n==== [1] 写入测试代码 sw x1,0(x2) @0x10200 + j-self ====\n"
set {int}0x10200 = 0x00112023
set {int}0x10204 = 0x0000006f
set {int}0x10208 = 0x0000006f
set $x1 = 0xdeadbeef
set $x2 = 0x00020000
set {int}0x00020000 = 0xcafebabe
set $pc = 0x10200
flushregs
p/x $x1
p/x $x2
x/1wx 0x00020000

printf "\n==== [2] watch 0x20000, continue ====\n"
watch *(int*)0x00020000
continue
flushregs
p/x $pc
info breakpoints
p/x *(int*)0x00020000

printf "\n==== [3] 清理 ====\n"
delete breakpoints
detach
quit
