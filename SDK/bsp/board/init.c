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
    soc_init();

    /* UART 初始化（唯一调用点，避免 __udivdi3 破坏 gp） */
    uart_init(115200);

    /* 设置中断向量表 (Vectored 模式) */
    __asm__ volatile(
        ".option push\n"
        ".option norelax\n"
        "la a0, __vector_table\n"
        "ori a0, a0, 1\n"
        "csrw mtvec, a0\n"
        ".option pop\n"
    );

    board_init();

    /* 使能 mcycle + minstret + HPM counters */
    __asm__ volatile("li a0, %0\n"
                     "csrrs x0, mcounteren, a0\n"
                     : : "i"((1 << 0) | (1 << 2) | (1 << 3) | (1 << 4) | (1 << 5) |
                             (1 << 6) | (1 << 7) | (1 << 8) | (1 << 9)));

}
