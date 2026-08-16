/*
 * BD32 RT-Thread v3.1.5 BSP —— 板级初始化 / tick / 控制台 / trap 分发
 *
 * 与 bsp/rtthread51/board.c（v5.1.0）内容一致，仅配套 3.1.5 内核。
 *
 * 中断架构（官方 CH32 模式）：
 *   7/11 号（定时器/外部）→ 轻量入口（rt_trap.S）：只存 caller 寄存器，
 *   处理完 mret；需要切换时 rt_hw_context_switch_interrupt 置 flag 并写
 *   CLINT_MSIP 触发软件中断。
 *   3 号软件中断 → SW_handler（interrupt_gcc.S）：全量保存 + flag 切换，
 *   延迟切换在此完成（PendSV 模式）。
 */
#include <rthw.h>
#include <rtthread.h>

#include "bsp.h"

/* trap_handler.c 中的弱定义（board.c 强定义 tmr_irq_handler 覆盖） */
void ext_irq_handler(void);
void sw_irq_handler(void);
void serr_handler(uint32_t mcause, uint32_t mepc);

/* 强定义覆盖 trap_handler.c 弱函数：打印异常信息后挂起（调试用） */
void serr_handler(uint32_t mcause, uint32_t mepc)
{
    rt_thread_t self = rt_thread_self();
    uart_puts("\r\n[SERR] thread=");
    if (self) uart_puts(self->name);
    if (self) {
        uart_puts(" tcb_sp=0x");
        uart_puthex((uint32_t)self->sp);
    }
    uart_puts("\r\n[SERR] mcause=0x");
    uart_puthex(mcause);
    uart_puts(" mepc=0x");
    uart_puthex(mepc);
    uart_puts(" mtval=0x");
    uart_puthex(core_get_mtval());
    uart_puts("\r\n");
    while (1);
}

/* ===================================================================
 * 系统节拍：CLINT mtime（1MHz）+ mtimecmp 机器定时器中断
 * =================================================================== */
#define TICK_PERIOD_TICKS   (SOC_TIMER_FREQ / RT_TICK_PER_SECOND)  /* 1ms @1MHz */

static inline void tick_reload(void)
{
    uint64_t now = ((uint64_t)CLINT_MTIME_HI << 32) | CLINT_MTIME_LO;
    uint64_t nxt = now + TICK_PERIOD_TICKS;
    /* 先写 HI 再写 LO（RISC-V CLINT 规范） */
    CLINT_MTIMECMP_HI = (uint32_t)(nxt >> 32);
    CLINT_MTIMECMP_LO = (uint32_t)(nxt & 0xFFFFFFFF);
}

/* 覆盖 trap_handler.c 中的弱定义 */
void tmr_irq_handler(void)
{
    tick_reload();
    rt_tick_increase();
}

#ifdef RT_USING_UNIFIED_IRQ
/* 统一入口模式（--irq-mode unified）的中断分发：按 mcause 低 5 位路由 */
void bd32_irq_dispatch(uint32_t mcause, uint32_t mepc, void *frame)
{
    (void)mepc;
    (void)frame;
    switch (mcause & 0x1F) {
    case 3:  sw_irq_handler();   break;   /* 机器软件中断 */
    case 7:  tmr_irq_handler();  break;   /* 机器定时器中断 */
    case 11: ext_irq_handler();  break;   /* 机器外部中断 */
    default: break;
    }
}
#endif

/* ===================================================================
 * 软件中断触发/清除（SW_handler 延迟切换路径）
 * =================================================================== */
#ifdef RT_USING_UNIFIED_IRQ
/* 统一入口模式：中断返回时直接检查 flag 切换，无需软件中断 */
void rt_trigger_software_interrupt(void) {}
void rt_hw_do_after_save_above(void) {}
#else
/* 覆盖 cpuport.c 的 weak 空实现：写 CLINT_MSIP 触发机器软件中断 */
void rt_trigger_software_interrupt(void)
{
    CLINT_MSIP = 1;
}

/* SW_handler 保存上下文后调用：清软件中断挂起即可（实际中断已在轻量入口处理） */
void rt_hw_do_after_save_above(void)
{
    CLINT_MSIP = 0;
}
#endif

/* ===================================================================
 * 控制台
 * =================================================================== */
#ifdef RT_USING_CONSOLE
void rt_hw_console_output(const char *str)
{
    uart_puts(str);
}

char rt_hw_console_getchar(void)
{
    if (UART_LSR & LSR_DR)
        return (char)(UART_RBR_THR & 0xFF);
    return -1;
}
#endif

/* ===================================================================
 * 板级初始化（rtthread_startup 内部调用）
 * =================================================================== */
void rt_hw_board_init(void)
{
    /* 配置 mtimecmp 并打开定时器中断（tick = 1ms） */
    tick_reload();
    /* MSIE：软件中断（SW_handler 延迟切换）必须使能 */
    core_enable_irq(MIE_MTIE | MIE_MSIE);

#ifdef RT_USING_HEAP
    /* 堆区由链接脚本提供（link.ld 的 .heap 段） */
    extern char __heap_start[];
    extern char __heap_end[];
    rt_system_heap_init(__heap_start, __heap_end);
#endif
}
