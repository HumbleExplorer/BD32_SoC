# BD32 UART + DTCM 对照测试
# 1. 发送 'A'（硬编码）
# 2. 从 DTCM 0x20000 读 1 字节并发送
# 3. 发 '\n'
# 4. 循环

.eqv UART_BASE,  0xE0010000
.eqv UART_THR,   0x00
.eqv UART_LSR,   0x14
.eqv DTCM_BASE,  0x00020000

.text
.align 4
.global _start

_start:
    li   t0, UART_BASE
    # === 第 1 步：发送硬编码 'A' ===
    li   t2, 0x41
1:  lw   t3, UART_LSR(t0)
    andi t3, t3, 0x20
    beqz t3, 1b
    sw   t2, UART_THR(t0)

    # === 第 2 步：从 DTCM 0x20000 读字节并发送 ===
    li   t1, DTCM_BASE
    lb   t2, 0(t1)               # 从 DTCM 读

2:  lw   t3, UART_LSR(t0)
    andi t3, t3, 0x20
    beqz t3, 2b
    sw   t2, UART_THR(t0)        # 发 DTCM 读到的值

    # === 第 3 步：发 '\n' ===
    li   t2, 0x0A
3:  lw   t3, UART_LSR(t0)
    andi t3, t3, 0x20
    beqz t3, 3b
    sw   t2, UART_THR(t0)

4:  j 4b

# DTCM 测试数据：在 0x20000 存放 "OK\r\n\0"
.section .rodata
.balign 4
msg:
    .ascii "OK\r\n\0"
