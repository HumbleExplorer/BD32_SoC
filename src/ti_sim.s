# 极简定时器中断仿真测试
# mtimecmp = mtime + 100 (约 1us @ 100MHz)
# 在 handler 里写 0xDEADBEEF 到 GPIO_OUT 作为触发标志
# 整个程序 ~30 条指令
#
# 编译：
#   riscv64-unknown-elf-gcc -c -march=rv32im -mabi=ilp32 \
#     src/ti_sim.s -o /tmp/ti_sim.o
#   riscv64-unknown-elf-gcc -march=rv32im -mabi=ilp32 \
#     -nostartfiles -nodefaultlibs -T lib/link.ld \
#     /tmp/ti_sim.o -o /tmp/ti_sim.elf
#
# 仿真用 testbench 直接读 ELF (ITCM 加载):
#   cp /tmp/ti_sim.elf test_data/custom/ti_sim.elf

.equ CLINT_BASE,    0xF2000000
.equ MTIME_LO,      0xBFF8
.equ MTIME_HI,      0xBFFC
.equ MTIMECMP_LO,   0x4000
.equ MTIMECMP_HI,   0x4004
.equ GPIO_OUT,      0xE0000008
.equ LED_MASK,      0x18
.equ HALF_SEC,      50000000      # 500ms @ 100MHz

.section .init
.global _start

_start:
    la   sp, _estack

    # mtvec = handler (Direct)
    la   a0, handler
    csrw mtvec, a0

    # t0 = CLINT_BASE
    li   s0, CLINT_BASE
    li   t0, MTIME_LO
    add  t0, s0, t0
    lw   t1, 0(t0)           # t1 = mtime[31:0]
    li   t2, HALF_SEC
    add  t1, t1, t2          # target = mtime + 1ms

    # 写 mtimecmp = target (先 hi 再 lo)
    li   t0, MTIMECMP_HI
    add  t0, s0, t0
    sw   zero, 0(t0)         # mtimecmp_hi = 0
    li   t0, MTIMECMP_LO
    add  t0, s0, t0
    sw   t1, 0(t0)           # mtimecmp_lo = mtime + 1ms

    # 开中断
    li   t1, 0x80            # mie[7] = MTIE
    csrw mie, t1
    li   t1, 0x1888          # mstatus: MIE=1
    csrw mstatus, t1

    # 初始化 GPIO: 设方向 + 初始灭
    li   t0, 0xE0000004       # GPIO_DIR
    li   t1, LED_MASK
    sw   t1, 0(t0)
    li   t0, GPIO_OUT
    sw   zero, 0(t0)          # GPIO_OUT = 0 (灭)
    li   t1, 0x0              # 不写固定值了

    # 无限循环
1:  j 1b

# ================================================================
# 中断处理
# ================================================================
.align 4
handler:
    # 保存用到的寄存器
    addi sp, sp, -16
    sw   t0, 0(sp)
    sw   t1, 4(sp)
    sw   s0, 8(sp)
    sw   t2, 12(sp)

    # 翻转 LED (GPIO_OUT ^= LED_MASK)
    li   t0, GPIO_OUT
    lw   t1, 0(t0)
    xori t1, t1, LED_MASK
    sw   t1, 0(t0)

    # 更新 mtimecmp = mtime + 1ms
    li   s0, CLINT_BASE
    li   t0, MTIME_LO
    add  t0, s0, t0
    lw   t1, 0(t0)           # t1 = mtime[31:0]
    li   t2, HALF_SEC
    add  t2, t1, t2          # t2 = mtime + 1ms

    li   t0, MTIMECMP_HI
    add  t0, s0, t0
    sw   zero, 0(t0)          # mtimecmp_hi = 0
    li   t0, MTIMECMP_LO
    add  t0, s0, t0
    sw   t2, 0(t0)            # mtimecmp_lo = 重新设

    # 恢复
    lw   t0, 0(sp)
    lw   t1, 4(sp)
    lw   s0, 8(sp)
    lw   t2, 12(sp)
    addi sp, sp, 16
    mret
