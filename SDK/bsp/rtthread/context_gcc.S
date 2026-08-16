/*
 * BD32 RT-Thread v3.1.5 RISC-V 上下文切换（官方 lts-v3.1.x unify port）
 *
 * 来源：RT-Thread 官方 lts-v3.1.x 分支 libcpu/risc-v/common/context_gcc.S，Apache-2.0。
 *
 * BD32 适配：
 *   1. rt_hw_context_switch_to 入口补两行 mscratch 初始化——
 *      轻量入口 + SW_handler（PendSV）方案要求 mscratch 指向中断栈
 *      __rt_rvstack，首次调度前必须建立，否则首个软件中断会踩 0 地址。
 *   2. 栈帧布局与 v5.1 一致：32 字，[0]=mepc [1]=ra [2]=mstatus
 *      [3]=保留 [4]=tp [5..31]=x5..x31。
 */

/*
 * rt_base_t rt_hw_interrupt_disable(void);
 */
    .globl rt_hw_interrupt_disable
rt_hw_interrupt_disable:
    csrrci  a0, mstatus, 8
    ret

/*
 * void rt_hw_interrupt_enable(rt_base_t level);
 */
    .globl rt_hw_interrupt_enable
rt_hw_interrupt_enable:
    csrw    mstatus, a0
    ret

/*
 * void rt_hw_context_switch_to(rt_uint32 to);
 *
 * a0 --> to
 */
    .globl rt_hw_context_switch_to
rt_hw_context_switch_to:
    la      t0, __rt_rvstack
    csrw    mscratch, t0

    lw      sp, 0(a0)

    lw      a0,   2*4(sp)
    csrw    mstatus, a0

    j       _thread_exit

/*
 * void rt_hw_context_switch(rt_uint32 from, rt_uint32 to);
 *
 * a0 --> from
 * a1 --> to
 */
    .globl rt_hw_context_switch
rt_hw_context_switch:
_thread_save:
    addi    sp, sp, -32*4
    sw      sp, 0(a0)

    sw      x1,   0*4(sp)
    sw      x1,   1*4(sp)

    csrr    a0, mstatus
    andi    a0, a0, 8
    beqz    a0, _thread_mpie_xx00
_thread_mpie_xx08:
    li      a0, 0x0088
    j       _thread_mpie
_thread_mpie_xx00:
    li      a0, 0
_thread_mpie:
    sw      a0,   2*4(sp)

    sw      x4,   4*4(sp)
    sw      x5,   5*4(sp)
    sw      x6,   6*4(sp)
    sw      x7,   7*4(sp)
    sw      x8,   8*4(sp)
    sw      x9,   9*4(sp)
    sw      x10, 10*4(sp)
    sw      x11, 11*4(sp)
    sw      x12, 12*4(sp)
    sw      x13, 13*4(sp)
    sw      x14, 14*4(sp)
    sw      x15, 15*4(sp)
    sw      x16, 16*4(sp)
    sw      x17, 17*4(sp)
    sw      x18, 18*4(sp)
    sw      x19, 19*4(sp)
    sw      x20, 20*4(sp)
    sw      x21, 21*4(sp)
    sw      x22, 22*4(sp)
    sw      x23, 23*4(sp)
    sw      x24, 24*4(sp)
    sw      x25, 25*4(sp)
    sw      x26, 26*4(sp)
    sw      x27, 27*4(sp)
    sw      x28, 28*4(sp)
    sw      x29, 29*4(sp)
    sw      x30, 30*4(sp)
    sw      x31, 31*4(sp)

    lw      sp, 0(a1)

_thread_exit:
    lw      a0,   0*4(sp)
    csrw    mepc, a0

    lw      x1,   1*4(sp)

    li      t0, 0x1800
    csrw    mstatus, t0
    lw      t0,   2*4(sp)
    csrs    mstatus, t0

    lw      x4,   4*4(sp)
    lw      x5,   5*4(sp)
    lw      x6,   6*4(sp)
    lw      x7,   7*4(sp)
    lw      x8,   8*4(sp)
    lw      x9,   9*4(sp)
    lw      x10, 10*4(sp)
    lw      x11, 11*4(sp)
    lw      x12, 12*4(sp)
    lw      x13, 13*4(sp)
    lw      x14, 14*4(sp)
    lw      x15, 15*4(sp)
    lw      x16, 16*4(sp)
    lw      x17, 17*4(sp)
    lw      x18, 18*4(sp)
    lw      x19, 19*4(sp)
    lw      x20, 20*4(sp)
    lw      x21, 21*4(sp)
    lw      x22, 22*4(sp)
    lw      x23, 23*4(sp)
    lw      x24, 24*4(sp)
    lw      x25, 25*4(sp)
    lw      x26, 26*4(sp)
    lw      x27, 27*4(sp)
    lw      x28, 28*4(sp)
    lw      x29, 29*4(sp)
    lw      x30, 30*4(sp)
    lw      x31, 31*4(sp)

    addi    sp, sp, 32*4

    mret
