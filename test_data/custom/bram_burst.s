# DTCM BRAM 25字批量测试 — 和 printf 版相同字数
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
    li   t4, 25                 # 读 25 个字

loop:
    lw   t2, 0(t1)

    li   t5, 4
byte_loop:
    andi t6, t2, 0x0F
    li   t3, 0xA
    blt  t6, t3, hd
    addi t6, t6, 0x57
    j    sh
hd: addi t6, t6, 0x30
sh: lw   t3, UART_LSR(t0)
    andi t3, t3, 0x20
    beqz t3, sh
    sw   t6, UART_THR(t0)
    srli t2, t2, 4
    addi t5, t5, -1
    bnez t5, byte_loop

    li   t2, 0x20
swa:lw   t3, UART_LSR(t0)
    andi t3, t3, 0x20
    beqz t3, swa
    sw   t2, UART_THR(t0)

    addi t1, t1, 4
    addi t4, t4, -1
    bnez t4, loop

    li   t2, 0x0A
nla:lw   t3, UART_LSR(t0)
    andi t3, t3, 0x20
    beqz t3, nla
    sw   t2, UART_THR(t0)

    j done

.section .rodata
.balign 4
msg:
    .word 0x00000000, 0x11111111, 0x22222222, 0x33333333, 0x44444444
    .word 0x55555555, 0x66666666, 0x77777777, 0x88888888, 0x99999999
    .word 0xAAAAAAAA, 0xBBBBBBBB, 0xCCCCCCCC, 0xDDDDDDDD, 0xEEEEEEEE
    .word 0xFFFFFFFF, 0x01234567, 0x89ABCDEF, 0xFEDCBA98, 0x76543210
    .word 0xDEADBEEF, 0xCAFEBABE, 0xBAADF00D, 0xAAAAAAAA, 0xBBBBBBBB

done:
    j done
