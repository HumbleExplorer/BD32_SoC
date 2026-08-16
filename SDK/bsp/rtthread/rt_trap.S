/*
 * BD32 RT-Thread v3.1.5 向量表 + 轻量中断入口
 *
 * 架构（官方 CH32 模式）：
 *   - 3 号软件中断 → SW_handler（interrupt_gcc.S，mscratch 切中断栈，
 *     全量保存 + flag 切换）——RT-Thread 的延迟切换在此完成
 *   - 7/11 号（定时器/外部）→ 轻量入口：只保存 caller 寄存器，
 *     处理完 mret；需要切换时 rt_hw_context_switch_interrupt 置 flag 并
 *     写 CLINT_MSIP 触发软件中断
 *   - 同步异常（表项 0）→ 打印后挂起
 *
 * 注：与 bsp/rtthread51/rt_trap.S（v5.1.0）内容一致，仅去掉无用且依赖
 * v5.1 cpuport.h 的 #include "cpuport.h"（本文件未使用其宏）。
 */
.section .trap.vector, "ax"
.align 4
.global __vector_table
__vector_table:
    j exc_entry              /*  0: 同步异常 */
    j irq_unhandled          /*  1 */
    j irq_unhandled          /*  2 */
#ifdef RT_USING_UNIFIED_IRQ
    j unified_irq            /*  3: 机器软件中断（统一入口：全量保存 + 直接切换） */
#else
    j SW_handler             /*  3: 机器软件中断（延迟切换） */
#endif
    j irq_unhandled          /*  4 */
    j irq_unhandled          /*  5 */
    j irq_unhandled          /*  6 */
#ifdef RT_USING_UNIFIED_IRQ
    j unified_irq            /*  7: 机器定时器中断（统一入口） */
#else
    j light_timer            /*  7: 机器定时器中断（轻量） */
#endif
    j irq_unhandled          /*  8 */
    j irq_unhandled          /*  9 */
    j irq_unhandled          /* 10 */
#ifdef RT_USING_UNIFIED_IRQ
    j unified_irq            /* 11: 机器外部中断（统一入口） */
#else
    j light_external         /* 11: 机器外部中断（轻量） */
#endif
    .rept 20
    j irq_unhandled
    .endr

.section .text
.align 2
.global exc_entry
exc_entry:
    /* 同步异常：打印 mcause/mepc 后挂起（复用 C 的 serr_handler） */
    addi sp, sp, -8
    sw   ra, 0(sp)
    csrr a0, mcause
    csrr a1, mepc
    call serr_handler
    lw   ra, 0(sp)
    addi sp, sp, 8
    mret

.global irq_unhandled
irq_unhandled:
    wfi
    j irq_unhandled

/* ============================================================
 * 轻量中断入口：只保存 caller 寄存器（不切换，返回原上下文）
 * 处理在中断栈上运行（trap_entry 之后 mscratch 已指向 __rt_rvstack）
 * ============================================================ */
.macro LIGHT_IRQ name, handler
.align 2
.global \name
\name:
    addi sp, sp, -17*4
    sw   ra, 0(sp)
    sw   tp, 4(sp)
    sw   t0, 8(sp)
    sw   t1, 12(sp)
    sw   t2, 16(sp)
    sw   a0, 20(sp)
    sw   a1, 24(sp)
    sw   a2, 28(sp)
    sw   a3, 32(sp)
    sw   a4, 36(sp)
    sw   a5, 40(sp)
    sw   a6, 44(sp)
    sw   a7, 48(sp)
    sw   t3, 52(sp)
    sw   t4, 56(sp)
    sw   t5, 60(sp)
    sw   t6, 64(sp)

    call rt_interrupt_enter
    call \handler
    call rt_interrupt_leave

    lw   ra, 0(sp)
    lw   tp, 4(sp)
    lw   t0, 8(sp)
    lw   t1, 12(sp)
    lw   t2, 16(sp)
    lw   a0, 20(sp)
    lw   a1, 24(sp)
    lw   a2, 28(sp)
    lw   a3, 32(sp)
    lw   a4, 36(sp)
    lw   a5, 40(sp)
    lw   a6, 44(sp)
    lw   a7, 48(sp)
    lw   t3, 52(sp)
    lw   t4, 56(sp)
    lw   t5, 60(sp)
    lw   t6, 64(sp)
    addi sp, sp, 17*4
    mret
.endm

LIGHT_IRQ light_timer, tmr_irq_handler
LIGHT_IRQ light_external, ext_irq_handler

#ifdef RT_USING_UNIFIED_IRQ
/* ============================================================
 * 统一中断入口（--irq-mode unified）：3/7/11 全部走这里
 *   全量保存 32 个 GPR + mepc/mstatus 到线程栈 → C 分发
 *   （bd32_irq_dispatch，直接在被打断线程栈上运行，不切中断栈）→
 *   返回时检查切换 flag，需要切换直接装载 to 线程栈。
 *   无软件中断依赖，也不依赖 mscratch。
 *   栈帧布局与 context_gcc.S / SW_handler 一致。
 * ============================================================ */
.section .text
.align 2
.global unified_irq
unified_irq:
    /* save all from thread context */
    addi sp, sp, -32*4
    sw   x1,   1*4(sp)
    csrr x1, mstatus
    sw   x1,   2*4(sp)
    csrr x1, mepc
    sw   x1,   0*4(sp)
    sw   x4,   4*4(sp)
    sw   x5,   5*4(sp)
    sw   x6,   6*4(sp)
    sw   x7,   7*4(sp)
    sw   x8,   8*4(sp)
    sw   x9,   9*4(sp)
    sw   x10, 10*4(sp)
    sw   x11, 11*4(sp)
    sw   x12, 12*4(sp)
    sw   x13, 13*4(sp)
    sw   x14, 14*4(sp)
    sw   x15, 15*4(sp)
    sw   x16, 16*4(sp)
    sw   x17, 17*4(sp)
    sw   x18, 18*4(sp)
    sw   x19, 19*4(sp)
    sw   x20, 20*4(sp)
    sw   x21, 21*4(sp)
    sw   x22, 22*4(sp)
    sw   x23, 23*4(sp)
    sw   x24, 24*4(sp)
    sw   x25, 25*4(sp)
    sw   x26, 26*4(sp)
    sw   x27, 27*4(sp)
    sw   x28, 28*4(sp)
    sw   x29, 29*4(sp)
    sw   x30, 30*4(sp)
    sw   x31, 31*4(sp)

    /* 线程栈指针暂存 s0（s0 原值已保存在 frame[8]），处理直接在栈上进行 */
    mv   s0, sp

    call rt_interrupt_enter
    csrr a0, mcause
    csrr a1, mepc
    mv   a2, s0
    call bd32_irq_dispatch
    call rt_interrupt_leave

    mv   sp, s0

    /* 需要切换：保存 from / 装载 to（直接切换，无软件中断） */
    la   s0, rt_thread_switch_interrupt_flag
    lw   s2, 0(s0)
    beqz s2, 1f
    sw   zero, 0(s0)

    csrr a0, mepc
    sw   a0, 0*4(sp)

    la   s0, rt_interrupt_from_thread
    lw   s1, 0(s0)
    sw   sp, 0(s1)

    la   s0, rt_interrupt_to_thread
    lw   s1, 0(s0)
    lw   sp, 0(s1)

    lw   a0, 0*4(sp)
    csrw mepc, a0

1:
    lw   x1,   1*4(sp)
    li   t0, 0x1800
    csrw mstatus, t0
    lw   t0,   2*4(sp)
    csrs mstatus, t0
    lw   x4,   4*4(sp)
    lw   x5,   5*4(sp)
    lw   x6,   6*4(sp)
    lw   x7,   7*4(sp)
    lw   x8,   8*4(sp)
    lw   x9,   9*4(sp)
    lw   x10, 10*4(sp)
    lw   x11, 11*4(sp)
    lw   x12, 12*4(sp)
    lw   x13, 13*4(sp)
    lw   x14, 14*4(sp)
    lw   x15, 15*4(sp)
    lw   x16, 16*4(sp)
    lw   x17, 17*4(sp)
    lw   x18, 18*4(sp)
    lw   x19, 19*4(sp)
    lw   x20, 20*4(sp)
    lw   x21, 21*4(sp)
    lw   x22, 22*4(sp)
    lw   x23, 23*4(sp)
    lw   x24, 24*4(sp)
    lw   x25, 25*4(sp)
    lw   x26, 26*4(sp)
    lw   x27, 27*4(sp)
    lw   x28, 28*4(sp)
    lw   x29, 29*4(sp)
    lw   x30, 30*4(sp)
    lw   x31, 31*4(sp)

    addi sp, sp, 32*4
    mret
#endif /* RT_USING_UNIFIED_IRQ */
