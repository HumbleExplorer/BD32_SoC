# 100MHz UART TX 稳定性测试 — 只输出 OKOKOKOKOK
.eqv UART_BASE,  0xE0010000
.eqv UART_THR,   0x00
.eqv UART_LSR,   0x14

.text
.align 4
.global _start

_start:
    li   t0, UART_BASE
    li   t1, 100               # 简单延迟，让 UART 稳定
1:  addi t1, t1, -1
    bnez t1, 1b

    li   t2, 0x4F              # 'O'
    li   t3, 0x4B              # 'K'

    # 发 O K 各 5 次
    li   t4, 5
2:  # 等待 THR 空
    lw   t5, UART_LSR(t0)
    andi t5, t5, 0x20
    beqz t5, 2b
    sw   t2, UART_THR(t0)     # 发 'O'

3:  lw   t5, UART_LSR(t0)
    andi t5, t5, 0x20
    beqz t5, 3b
    sw   t3, UART_THR(t0)     # 发 'K'

    addi t4, t4, -1
    bnez t4, 2b

    # 发 '\r\n'
    li   t2, 0x0D
4:  lw   t5, UART_LSR(t0)
    andi t5, t5, 0x20
    beqz t5, 4b
    sw   t2, UART_THR(t0)

    li   t2, 0x0A
5:  lw   t5, UART_LSR(t0)
    andi t5, t5, 0x20
    beqz t5, 5b
    sw   t2, UART_THR(t0)

6:  j 6b
