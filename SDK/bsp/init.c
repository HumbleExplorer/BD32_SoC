/*
 * BD32 系统初始化
 * 参考 Panda RISC-V / tinyriscv init.c
 *
 * 在 start.s 的 _start 之后、main 之前被调用
 * 完成：设置 mtvec, 可选使能全局中断
 */

#include "bsp.h"


extern void __vector_table(void);

/* 弱定义：用户可在 main 前重写 board_init */
void __attribute__((weak)) board_init(void) {
    /* 空的板级初始化，用户可覆盖 */
}

void _init(void) {
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

    /* 使能 mcycle CSR 读取（BD32 的 mcycle 受 mcounteren[0] 控制，复位为 0） */
    set_csr(mcounteren, 1);

    /* 注意：这里不开 mstatus.MIE！
     * 由应用程序在 main 中合适时机手动开启：
     *   core_global_irq_enable();
     */
}
