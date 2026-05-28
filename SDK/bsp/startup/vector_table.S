/* BD32 中断向量表 (Vectored Mode)
 *
 * 配合 mtvec.MODE=1 使用，硬件自动分发中断到对应表项
 * 每个表项 4 字节（一条 j 指令）
 *
 * RISC-V 向量模式行为：
 *   同步异常 → PC = mtvec.BASE
 *   中断     → PC = mtvec.BASE + 4 * cause
 *
 * 中断原因码 (mcause bits 30:0):
 *   3  — 机器软件中断
 *   7  — 机器定时器中断
 *   11 — 机器外部中断
 *
 * 使用说明：
 *   1. 编译时加入 vector_table.o
 *   2. init.c 中设置 mtvec = __vector_table | 1
 */

    .section .trap.vector, "ax"
    .align 4
    .global __vector_table
    .type __vector_table, @object
__vector_table:
    /*  0 */  j exc_entry              /* 同步异常入口 */
    /*  1 */  j irq_unhandled          /* 保留 */
    /*  2 */  j irq_unhandled          /* 保留 */
    /*  3 */  j irq_software_entry     /* 机器软件中断 */
    /*  4 */  j irq_unhandled          /* 保留 */
    /*  5 */  j irq_unhandled          /* 保留 */
    /*  6 */  j irq_unhandled          /* 保留 */
    /*  7 */  j irq_timer_entry        /* 机器定时器中断 */
    /*  8 */  j irq_unhandled          /* 保留 */
    /*  9 */  j irq_unhandled          /* 保留 */
    /* 10 */  j irq_unhandled          /* 保留 */
    /* 11 */  j irq_external_entry     /* 机器外部中断 */
    /* 12~31: 保留中断 */
    .rept 20
    j irq_unhandled
    .endr
    .size __vector_table, . - __vector_table

/* ================================================================
 * 同步异常入口（vectored 模式下仅处理同步异常）
 * 硬件已自动将 PC 指向 mtvec.BASE（即 entry 0）
 * 直接保存上下文，调 C 的 serr_handler，恢复，mret
 * ================================================================ */
    .section .text
    .align 2
    .global exc_entry
    .type exc_entry, @function
exc_entry:
    addi sp, sp, -80           /* 20 regs × 4 */
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

    csrr a0, mcause
    csrr a1, mepc
    call serr_handler

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
    addi sp, sp, 80

    mret
    .size exc_entry, . - exc_entry

/* ================================================================
 * 中断快速入口宏
 * 硬件已将 PC 指向 mtvec.BASE + 4*cause，无需查 mcause
 * 直接保存上下文 → 调对应的 C handler → 恢复 → mret
 *
 * 相比 direct 模式省去了 mcause 读取 + if-else 分发逻辑
 * ================================================================ */
.macro IRQ_ENTRY name, handler_fn
    .section .text
    .align 2
    .globl \name
    .type \name, @function
\name:
    addi sp, sp, -80
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

    call \handler_fn

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
    addi sp, sp, 80

    mret
    .size \name, . - \name
.endm

IRQ_ENTRY irq_timer_entry,    tmr_irq_handler
IRQ_ENTRY irq_software_entry, sw_irq_handler
IRQ_ENTRY irq_external_entry, ext_irq_handler

/* ================================================================
 * 未处理中断
 * 保留中断源意外触发时陷入 wfi
 * ================================================================ */
    .section .text
    .align 2
    .global irq_unhandled
    .type irq_unhandled, @function
irq_unhandled:
    wfi
    j irq_unhandled
    .size irq_unhandled, . - irq_unhandled
