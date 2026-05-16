# 极小 DTCM 读测试（纯汇编，自包含，不依赖 BSP）
# 1. UART init
# 2. 读 DTCM[0] (0x20000) 并打印十六进制
# 3. 读 DTCM[1] (0x20004) 并打印十六进制
# 4. 无限循环

.eqv UART_BASE,  0xE0010000
.eqv UART_LSR,   0xE0010014

.section .init
.global _start
_start:
    # UART init: 115200bps @ 100MHz
    li   t0, 0xE001000C
    li   t1, 0x80
    sw   t1, 0(t0)
    li   t0, 0xE0010000
    li   t1, 54
    sw   t1, 0(t0)
    sw   zero, 4(t0)
    li   t1, 0x03
    sw   t1, 0x0C(t0)

    # 打印 "DTCM: "
    li   t0, UART_LSR
1:  lw   t1, 0(t0)
    andi t1, t1, 0x20
    beqz t1, 1b
    li   t1, 0x44   # 'D'
    sw   t1, -0x14(t0)
    li   t0, UART_LSR
1:  lw   t1, 0(t0)
    andi t1, t1, 0x20
    beqz t1, 1b
    li   t1, 0x54   # 'T'
    sw   t1, -0x14(t0)
    li   t0, UART_LSR
1:  lw   t1, 0(t0)
    andi t1, t1, 0x20
    beqz t1, 1b
    li   t1, 0x43   # 'C'
    sw   t1, -0x14(t0)
    li   t0, UART_LSR
1:  lw   t1, 0(t0)
    andi t1, t1, 0x20
    beqz t1, 1b
    li   t1, 0x4D   # 'M'
    sw   t1, -0x14(t0)
    li   t0, UART_LSR
1:  lw   t1, 0(t0)
    andi t1, t1, 0x20
    beqz t1, 1b
    li   t1, 0x3A   # ':'
    sw   t1, -0x14(t0)
    li   t0, UART_LSR
1:  lw   t1, 0(t0)
    andi t1, t1, 0x20
    beqz t1, 1b
    li   t1, 0x20   # ' '
    sw   t1, -0x14(t0)

    # 读 DTCM[0] (0x20000)
    li   s0, 0x00020000
    lw   s1, 0(s0)

    # 打印 s1 的 8 位十六进制
    li   s2, 28
next_hex1:
    srl  a0, s1, s2
    andi a0, a0, 0xF
    li   t0, 10
    blt  a0, t0, is_digit1
    addi a0, a0, 0x37  # 'A' - 10
    j    print_hex1
is_digit1:
    addi a0, a0, 0x30  # '0'
print_hex1:
    li   t0, UART_LSR
1:  lw   t1, 0(t0)
    andi t1, t1, 0x20
    beqz t1, 1b
    sw   a0, -0x14(t0)
    addi s2, s2, -4
    bgez s2, next_hex1

    # 换行
    li   t0, UART_LSR
1:  lw   t1, 0(t0)
    andi t1, t1, 0x20
    beqz t1, 1b
    li   t1, 0x0A
    sw   t1, -0x14(t0)

    # 读 DTCM[1] (0x20004)
    lw   s1, 4(s0)

    li   t0, UART_LSR
1:  lw   t1, 0(t0)
    andi t1, t1, 0x20
    beqz t1, 1b
    li   t1, 0x44   # 'D'
    sw   t1, -0x14(t0)
    li   t0, UART_LSR
1:  lw   t1, 0(t0)
    andi t1, t1, 0x20
    beqz t1, 1b
    li   t1, 0x54   # 'T'
    sw   t1, -0x14(t0)
    li   t0, UART_LSR
1:  lw   t1, 0(t0)
    andi t1, t1, 0x20
    beqz t1, 1b
    li   t1, 0x43   # 'C'
    sw   t1, -0x14(t0)
    li   t0, UART_LSR
1:  lw   t1, 0(t0)
    andi t1, t1, 0x20
    beqz t1, 1b
    li   t1, 0x4D   # 'M'
    sw   t1, -0x14(t0)
    li   t0, UART_LSR
1:  lw   t1, 0(t0)
    andi t1, t1, 0x20
    beqz t1, 1b
    li   t1, 0x3A   # ':'
    sw   t1, -0x14(t0)
    li   t0, UART_LSR
1:  lw   t1, 0(t0)
    andi t1, t1, 0x20
    beqz t1, 1b
    li   t1, 0x20   # ' '
    sw   t1, -0x14(t0)

    li   s2, 28
next_hex2:
    srl  a0, s1, s2
    andi a0, a0, 0xF
    li   t0, 10
    blt  a0, t0, is_digit2
    addi a0, a0, 0x37
    j    print_hex2
is_digit2:
    addi a0, a0, 0x30
print_hex2:
    li   t0, UART_LSR
1:  lw   t1, 0(t0)
    andi t1, t1, 0x20
    beqz t1, 1b
    sw   a0, -0x14(t0)
    addi s2, s2, -4
    bgez s2, next_hex2

    li   t0, UART_LSR
1:  lw   t1, 0(t0)
    andi t1, t1, 0x20
    beqz t1, 1b
    li   t1, 0x0A
    sw   t1, -0x14(t0)

loop:
    j loop
