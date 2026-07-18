/*
 * BD32 系统初始化
 * 参考 Panda RISC-V / tinyriscv init.c
 *
 * 在 start.s 的 _start 之后、main 之前被调用
 * 完成：测主频、设置 mtvec、可选使能全局中断
 */
#include "bsp.h"

extern void __vector_table(void);

/* 运行时 CPU 主频（Hz），MROM 测量或 soc_init() 测量 */
uint32_t g_cpu_freq_hz;

/* 弱定义：用户可在 main 前重写 board_init */
void __attribute__((weak)) board_init(void) {
    /* 空的板级初始化，用户可覆盖 */
}

void _init(void) {
    /* === 测 CPU 主频（10ms） ===
     * 基于 CLINT mtime 1MHz 基准 + csr mcycle
     * 结果填入 g_cpu_freq_hz
     * 必须在任何延时/UART 使用前完成
     */
    soc_init();

    /* 设置中断向量表 (Vectored 模式) */
    /* mtvec.MODE = 1: 异常 PC=mtvec.BASE, 中断 PC=mtvec.BASE+4*cause */
    __asm__ volatile(
        ".option push\n"
        ".option norelax\n"
        "la a0, __vector_table\n"
        "ori a0, a0, 1\n"         /* MODE=1: Vectored */
        "csrw mtvec, a0\n"
        ".option pop\n"
    );

    /* 用户板级初始化 */
    board_init();

    /* 使能 mcycle + mhpm_counter3~9 CSR 读取 */
    /* bit 0 = mcycle, bit 2 = minstret */
    /* bit 3~9 = mhp_counter3~9 (ALU/LOAD/STORE/BRANCH/JUMP/MULDIV/PRED_OK) */
    __asm__ volatile("li a0, %0\n"
                     "csrrs x0, mcounteren, a0\n"
                     : : "i"((1 << 0) | (1 << 2) | (1 << 3) | (1 << 4) | (1 << 5) |
                             (1 << 6) | (1 << 7) | (1 << 8) | (1 << 9)));

    /* 注意：这里不开 mstatus.MIE！
     * 由应用程序在 main 中合适时机手动开启：
     *   core_global_irq_enable();
     */
}
