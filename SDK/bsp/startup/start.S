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

    /* MROM 已将 mcycle/mtime 测得的 CPU 频率写到 DTCM 0x2FFF0。
     * 必须在第一次 call/压栈之前读取：该地址位于栈顶预留区。
     * 先清 BSS，再写入 g_cpu_freq_hz，避免它被上面的清零循环覆盖。 */
    li   t0, 0x0002FFF0
    lw   t1, 0(t0)
    la   t0, g_cpu_freq_hz
    sw   t1, 0(t0)

    call _init
#ifdef RT_USING_RTTHREAD
    call rtthread_startup
#else
    call main
#endif
1:  j 1b

.size _start, .-_start
