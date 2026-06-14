/* BD32 复位 — 必须在 0x00010000，硬件复位向量固定地址 */
.section .reset, "ax"
.global _reset_vector
.type _reset_vector, @function
_reset_vector:
    j _start
.size _reset_vector, .-_reset_vector

/* BD32 启动入口 */
.section .init
.global _start
.type _start, @function

_start:
    .option push
    .option norelax
1:  auipc gp, %pcrel_hi(__global_pointer$)
    addi  gp, gp, %pcrel_lo(1b)
    la   sp, _estack
    la   a0, _sbss
    la   a1, _ebss
    .option pop

    beq  a0, a1, 2f
1:  sw   zero, 0(a0)
    addi a0, a0, 4
    bltu a0, a1, 1b
2:

    call _init
    call main
1:  j 1b

.size _start, .-_start
