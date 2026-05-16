# 纯汇编版 C环境验证 — 只打 ABC XYZ + 灭灯
# 不链接 start.o/init.o 等，跟 ti_sim.s 一样自包含

.equ UART_THR,   0xE0010000
.equ UART_LSR,   0xE0010014
.equ GPIO_DIR,   0xE0000004
.equ GPIO_OUT,   0xE0000008
.equ LED_MASK,   0x18

.section .init
.global _start
_start:
    la   sp, _estack

    # UART 初始化
    li   t0, 0xE0010000
    li   t1, 0x80
    sw   t1, 0x0C(t0)      # LCR = DLAB
    li   t1, 54
    sw   t1, 0x00(t0)      # DLL
    sw   zero, 0x04(t0)    # DLM
    li   t1, 0x03
    sw   t1, 0x0C(t0)      # LCR = 8N1

    # 打印 'A'
    li   a0, 0x41
    call uart_putc
    # 打印 'B'
    li   a0, 0x42
    call uart_putc
    # 打印 'C'
    li   a0, 0x43
    call uart_putc
    # 打印 '\n'
    li   a0, 0x0A
    call uart_putc

    # GPIO 初始化
    li   t0, GPIO_DIR
    li   t1, LED_MASK
    sw   t1, 0(t0)
    sw   zero, 0x4(t0)    # 实际是 GPIO_BASE, 这里改一下
    # 正确：GPIO_DIR=0xE0000004, GPIO_OUT=0xE0000008
    # 所以：sw 到 0xE0000004(DIR), 然后 sw 到 0xE0000008(OUT)
    li   t0, GPIO_OUT
    sw   zero, 0(t0)

    # 打印 'X'
    li   a0, 0x58
    call uart_putc
    # 打印 'Y'
    li   a0, 0x59
    call uart_putc
    # 打印 'Z'
    li   a0, 0x5A
    call uart_putc
    # 打印 '\n'
    li   a0, 0x0A
    call uart_putc

loop:
    j loop

uart_putc:
    li   t2, UART_LSR
1:  lw   t3, 0(t2)
    andi t3, t3, 0x20
    beqz t3, 1b
    li   t2, UART_THR
    sw   a0, 0(t2)
    ret
