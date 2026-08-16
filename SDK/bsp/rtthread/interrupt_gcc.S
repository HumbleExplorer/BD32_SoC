/*
 * BD32 RT-Thread v3.1.5 软件中断处理入口（SW_handler）
 *
 * 来源：官方 v5.1 libcpu/risc-v/common/interrupt_gcc.S 的 SW_handler，
 * 裁剪为纯 RV32（lw/sw）并去掉 trap_entry（BD32 用自带 rt_trap.S 向量表），
 * Apache-2.0。
 *
 * 流程（PendSV 模式，与 v5.1 相同）：
 *   进入后立即关 MIE → 全量保存 32 个 GPR 到线程栈 →
 *   csrrw sp, mscratch, sp 切到中断栈 → rt_interrupt_enter →
 *   rt_hw_do_after_save_above（清 MSIP）→ rt_interrupt_leave →
 *   切回线程栈 → 若 rt_thread_switch_interrupt_flag 置位则做延迟切换
 *   （保存 from 线程栈指针、装载 to 线程栈指针）→ 恢复现场 → mret。
 *
 * 栈帧布局与 context_gcc.S / cpuport.c 一致：
 *   [0]=mepc [1]=ra [2]=mstatus(0x80) [4]=tp [5..31]=x5..x31
 */

    .section .text.entry, "ax"
    .align  2
    .global SW_handler

SW_handler:
    csrci mstatus, 0x8
    /* save all from thread context */
    addi sp, sp, -32 * 4
    sw   x5,   5 * 4(sp)
    sw   x1,   1 * 4(sp)
    /* Mandatory set the MPIE of mstatus */
    li   t0,   0x80
    sw   t0,   2 * 4(sp)
    sw   x4,   4 * 4(sp)
    sw   x6,   6 * 4(sp)
    sw   x7,   7 * 4(sp)
    sw   x8,   8 * 4(sp)
    sw   x9,   9 * 4(sp)
    sw   x10, 10 * 4(sp)
    sw   x11, 11 * 4(sp)
    sw   x12, 12 * 4(sp)
    sw   x13, 13 * 4(sp)
    sw   x14, 14 * 4(sp)
    sw   x15, 15 * 4(sp)
    sw   x16, 16 * 4(sp)
    sw   x17, 17 * 4(sp)
    sw   x18, 18 * 4(sp)
    sw   x19, 19 * 4(sp)
    sw   x20, 20 * 4(sp)
    sw   x21, 21 * 4(sp)
    sw   x22, 22 * 4(sp)
    sw   x23, 23 * 4(sp)
    sw   x24, 24 * 4(sp)
    sw   x25, 25 * 4(sp)
    sw   x26, 26 * 4(sp)
    sw   x27, 27 * 4(sp)
    sw   x28, 28 * 4(sp)
    sw   x29, 29 * 4(sp)
    sw   x30, 30 * 4(sp)
    sw   x31, 31 * 4(sp)
    /* switch to interrupt stack */
    csrrw sp, mscratch, sp
    /* interrupt handle */
    call  rt_interrupt_enter
    /* Do the work after saving the above */
    jal   rt_hw_do_after_save_above

    call  rt_interrupt_leave
    /* switch to from thread stack */
    csrrw sp, mscratch, sp

    /* Determine whether to trigger scheduling at the interrupt function */
    la    t0, rt_thread_switch_interrupt_flag
    lw    t2, 0(t0)
    beqz  t2, 1f
    /* clear the flag of rt_thread_switch_interrupt_flag */
    sw    zero, 0(t0)

    csrr  a0, mepc
    sw    a0, 0 * 4(sp)

    la    t0, rt_interrupt_from_thread
    lw    t1, 0(t0)
    sw    sp, 0(t1)

    la    t0, rt_interrupt_to_thread
    lw    t1, 0(t0)
    lw    sp, 0(t1)

    lw    a0,  0 * 4(sp)
    csrw  mepc, a0

1:
    lw    x1,   1 * 4(sp)

    /* Set the mode after MRET */
    li    t0, 0x1800
    csrs  mstatus, t0
    lw    t0,   2 * 4(sp)
    csrs  mstatus, t0

    lw    x4,   4 * 4(sp)
    lw    x5,   5 * 4(sp)
    lw    x6,   6 * 4(sp)
    lw    x7,   7 * 4(sp)
    lw    x8,   8 * 4(sp)
    lw    x9,   9 * 4(sp)
    lw    x10, 10 * 4(sp)
    lw    x11, 11 * 4(sp)
    lw    x12, 12 * 4(sp)
    lw    x13, 13 * 4(sp)
    lw    x14, 14 * 4(sp)
    lw    x15, 15 * 4(sp)
    lw    x16, 16 * 4(sp)
    lw    x17, 17 * 4(sp)
    lw    x18, 18 * 4(sp)
    lw    x19, 19 * 4(sp)
    lw    x20, 20 * 4(sp)
    lw    x21, 21 * 4(sp)
    lw    x22, 22 * 4(sp)
    lw    x23, 23 * 4(sp)
    lw    x24, 24 * 4(sp)
    lw    x25, 25 * 4(sp)
    lw    x26, 26 * 4(sp)
    lw    x27, 27 * 4(sp)
    lw    x28, 28 * 4(sp)
    lw    x29, 29 * 4(sp)
    lw    x30, 30 * 4(sp)
    lw    x31, 31 * 4(sp)

    addi  sp, sp, 32 * 4

    mret
