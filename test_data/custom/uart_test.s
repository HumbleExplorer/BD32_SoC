# BD32 UART 测试 — 直接写死值到 UART，无 DTCM 依赖
.eqv UART_BASE,  0xE0010000
.eqv UART_THR,   0x00
.eqv UART_LSR,   0x14

.text
.align 4
.global _start

_start:
    li   t0, UART_BASE
    li   t2, 0x41              # 'A' — 硬编码，完全不用 DTCM

    # 等待 UART THR 空
1:  lw   t3, UART_LSR(t0)
    andi t3, t3, 0x20
    beqz t3, 1b

    sw   t2, UART_THR(t0)      # 发送 'A'

    # 再发一个换行
    li   t2, 0x0A
2:  lw   t3, UART_LSR(t0)
    andi t3, t3, 0x20
    beqz t3, 2b
    sw   t2, UART_THR(t0)

    # 死循环
3:  j 3b
