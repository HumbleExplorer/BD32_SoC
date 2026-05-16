/*
 * BD32 弱定义中断处理函数
 *
 * 配合 vector_table.S (Vectored 模式) 使用。
 * 向量表直接跳转到对应的快速入口，再由快速入口调用这些 C handler。
 *
 * 用户可在自己的 C 文件中重写任意一个弱定义 handler。
 */

#include "bd32.h"

/* 弱定义中断处理函数（用户可覆盖） */
void __attribute__((weak)) sw_irq_handler(void)  {}
void __attribute__((weak)) tmr_irq_handler(void) {}
void __attribute__((weak)) ext_irq_handler(void) {}

/* 同步异常处理（缺省死循环） */
void __attribute__((weak))
serr_handler(uint32_t mcause, uint32_t mepc) {
    (void)mcause;
    (void)mepc;
    while (1);
}
