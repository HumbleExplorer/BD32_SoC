# BD32 DTCM BRAM 批量写入测试
# 1. 从 0x20000 开始连续读 100 个字并发送
# 2. 每字前加 '#' 前缀方便定位

.eqv UART_BASE,  0xE0010000
.eqv UART_THR,   0x00
.eqv UART_LSR,   0x14
.eqv DTCM_BASE,  0x00020000

.text
.align 4
.global _start

_start:
    li   t0, UART_BASE
    li   t1, DTCM_BASE
    li   t4, 100                # 100 个字

loop:
    # 发 '#'
    li   t2, 0x23
1:  lw   t3, UART_LSR(t0)
    andi t3, t3, 0x20
    beqz t3, 1b
    sw   t2, UART_THR(t0)

    # 从 DTCM 读一个字
    lw   t2, 0(t1)

    # 逐个字节发送（小端序 LSB first）
    li   t5, 4
2:  andi t6, t2, 0xFF           # 取最低字节
    addi t6, t6, 0x30           # 转 ASCII (0x30-0x39, 0x3A-0x3F 当作 A-F)
    # 简单的 hex 转换 — 如果 <= 0x39 直接发，否则转字母
    andi t6, t2, 0xFF
    li   t3, 0xA
    blt  t6, t3, 3f
    addi t6, t6, 0x57           # 0xA -> 'a'
    j    4f
3:  addi t6, t6, 0x30           # 0x0 -> '0'
4:  lw   t3, UART_LSR(t0)
    andi t3, t3, 0x20
    beqz t3, 4b
    sw   t6, UART_THR(t0)

    srli t2, t2, 8              # 下一个字节
    addi t5, t5, -1
    bnez t5, 2b

    # 发 ' '
    li   t2, 0x20
5:  lw   t3, UART_LSR(t0)
    andi t3, t3, 0x20
    beqz t3, 5b
    sw   t2, UART_THR(t0)

    addi t1, t1, 4              # 下一个字
    addi t4, t4, -1
    bnez t4, loop

    # 发 '\n'
    li   t2, 0x0A
6:  lw   t3, UART_LSR(t0)
    andi t3, t3, 0x20
    beqz t3, 6b
    sw   t2, UART_THR(t0)

7:  j 7b

# DTCM 测试数据：256 个递增字 (0x00, 0x01, 0x02, ... 0xFF 循环)
.section .rodata
.balign 4
data:
    .word 0x03020100
    .word 0x07060504
    .word 0x0B0A0908
    .word 0x0F0E0D0C
    .word 0x13121110
    .word 0x17161514
    .word 0x1B1A1918
    .word 0x1F1E1D1C
    .word 0x23222120
    .word 0x27262524
    .word 0x2B2A2928
    .word 0x2F2E2D2C
    .word 0x33323130
    .word 0x37363534
    .word 0x3B3A3938
    .word 0x3F3E3D3C
    .word 0x43424140
    .word 0x47464544
    .word 0x4B4A4948
    .word 0x4F4E4D4C
    .word 0x53525150
    .word 0x57565554
    .word 0x5B5A5958
    .word 0x5F5E5D5C
    .word 0x63626160
    .word 0x67666564
    .word 0x6B6A6968
    .word 0x6F6E6D6C
    .word 0x73727170
    .word 0x77767574
    .word 0x7B7A7978
    .word 0x7F7E7D7C
