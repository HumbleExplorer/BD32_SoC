# 定时器中断验证 v2 — 极短 mtimecmp (+500≈5us)
# 纯轮询：如果 mtime ≥ mtimecmp 时中断不发生，那就至少能看到轮询触发？
# 
# 其实这版本是错的——我用轮询代替了中断验证，但中断触发时硬件会走异常路径
# 
# 正确做法：直接轮询检查 CSR mip[7] 是否置位
# 但读 CSR 需要权限，我们用 CLINT 直读 mtimecmp
#
# 这版的输出：
#   "S\n" 开始
#   每1000轮打印一个 "."
#   当 mtime ≥ mtimecmp 时打印 "T\n" + 翻转LED
#   然后设新的 mtimecmp = mtime + 2000

.equ UART_BASE,     0xE0010000
.equ UART_LSR,      0x14
.equ LSR_THRE,      0x20
.equ GPIO_BASE,     0xE0000000
.equ GPIO_OUT,      0x08
.equ LED_MASK,      0x18
.equ CLINT_BASE,    0xF2000000
.equ MTIME_LO,      0xBFF8
.equ MTIME_HI,      0xBFFC
.equ MTIMECMP_LO,   0x4000
.equ MTIMECMP_HI,   0x4004

.section .init
.global _start

_start:
    la   sp, _estack

    # UART
    li   s0, UART_BASE
    li   t1, 0x80; sw t1, 0x0C(s0)
    li   t1, 54;   sw t1, 0x00(s0)
    sw   zero, 0x04(s0)
    li   t1, 0x03; sw t1, 0x0C(s0)

    # GPIO
    li   s1, GPIO_BASE
    li   t1, LED_MASK; sw t1, 0x04(s1)
    sw   zero, 0x08(s1)

    li   s2, CLINT_BASE

    # 设 mtimecmp = mtime + 500
    li   t0, MTIME_LO;  add t0, s2, t0; lw t4, 0(t0)
    li   t0, MTIME_HI;  add t0, s2, t0; lw t5, 0(t0)
    addi t2, t4, 500
    sltu t3, t2, t4
    add  t3, t5, t3
    li   t0, MTIMECMP_HI;  add t0, s2, t0; sw t3, 0(t0)
    li   t0, MTIMECMP_LO;  add t0, s2, t0; sw t2, 0(t0)

    # 打印 "S\n"
    li   a0, 0x53; call uart_putc
    li   a0, 0x0A; call uart_putc

    # 主循环：轮询等 mtime ≥ mtimecmp
    li   s3, 0

loop:
    addi s3, s3, 1
    li   t0, 5000
    blt  s3, t0, check
    li   s3, 0
    li   a0, 0x2E   # '.'
    call uart_putc

check:
    li   t0, MTIME_LO;  add t0, s2, t0; lw t2, 0(t0)
    li   t0, MTIMECMP_LO; add t0, s2, t0; lw t3, 0(t0)
    bltu t2, t3, loop

    # mtime >= mtimecmp → "T!\n"
    li   a0, 0x54; call uart_putc   # 'T'
    li   a0, 0x21; call uart_putc   # '!'
    li   a0, 0x0A; call uart_putc

    # 翻转 LED
    lw   t0, GPIO_OUT(s1)
    xori t0, t0, LED_MASK
    sw   t0, GPIO_OUT(s1)

    # 设新 mtimecmp = mtime + 2000
    li   t0, MTIME_LO;  add t0, s2, t0; lw t4, 0(t0)
    li   t0, MTIME_HI;  add t0, s2, t0; lw t5, 0(t0)
    addi t2, t4, 2000
    sltu t3, t2, t4
    add  t3, t5, t3
    li   t0, MTIMECMP_HI;  add t0, s2, t0; sw t3, 0(t0)
    li   t0, MTIMECMP_LO;  add t0, s2, t0; sw t2, 0(t0)

    li   s3, 0
    j loop

uart_putc:
1:  lw t5, UART_LSR(s0)
    andi t5, t5, LSR_THRE
    beqz t5, 1b
    sw a0, 0x00(s0)
    ret
