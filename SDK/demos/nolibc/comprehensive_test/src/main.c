/*
 * Demo: 综合中断测试 — 定时器闪烁 + 按键触发呼吸灯
 *
 * 【实验现象】
 *   阶段 A（按键按下之前）：
 *     - LED0(H15) 按 500ms 频率闪烁      （Timer 中断驱动）
 *     - LED1(J16) 保持常亮               （GPIO 直接输出）
 *     - LED2(L15) 不亮                   （Timer PWM 关闭）
 *
 *   阶段 B（按下 KEY0 后）：
 *     - LED0 停止闪烁（Timer 中断关闭）  （GPIO 熄灭）
 *     - LED1 保持常亮                     （不变）
 *     - LED2 开始呼吸                     （Timer 重配置为 PWM 模式）
 *
 * 【架构】
 *   状态机：PHASE_BLINK → (KEY0 GPIO 中断) → PHASE_BREATH
 *   ISR 只设 flag，主循环做重配置和呼吸 PWM
 */
#include "bsp.h"
#include <stdint.h>

/* ---- 常量 ---- */
#define PLIC_SRC_GPIO   2
#define PLIC_SRC_TIMER  3
#define BLINK_HALF_MS   250     /* 250 × 2ms = 500ms 半周期 */
#define BREATH_STEP_US  3000    /* 呼吸每步 3ms */

/* ---- 状态机 ---- */
enum { PHASE_BLINK, PHASE_BREATH };
static volatile int  phase      = PHASE_BLINK;
static volatile int  blink_tick = 0;
static volatile int  btn_done   = 0;

/* ---- LED 引脚 ---- */
/* GPIO 上只有 LED0/1，LED2 是 Timer 硬件 PWM 输出(L15) */
#define PL_LED0  PIN_LED0   /* H15 — GPIO bit3 */
#define PL_LED1  PIN_LED1   /* J16 — GPIO bit4 */


/* ================================================================
 * 阶段 A：定时器中断 ISR  —  每 2ms 触发，计到半周期翻 LED0
 * ================================================================ */
static void timer_blink_isr(void)
{
    TIM_SR = 0x01;          /* 写 1 清更新中断标志 */

    blink_tick++;
    if (blink_tick >= BLINK_HALF_MS) {
        blink_tick = 0;
        GPIO_OUT ^= PL_LED0;      /* 翻转 LED0：250×2ms = 500ms */
    }
}


/* ================================================================
 * PLIC 外部中断入口  —  分发 GPIO / Timer 中断
 * ================================================================ */
void ext_irq_handler(void)
{
    uint32_t src = PLIC_CLAIM;

    switch (src) {
    case PLIC_SRC_TIMER:
        if (phase == PHASE_BLINK)
            timer_blink_isr();    /* 只在闪烁阶段响应 Timer */
        break;

    case PLIC_SRC_GPIO: {
        /* Opensoc GPIO 中断清除流程：先读后写 */
        (void)GPIO_TR_STAT;
        GPIO_TR_STAT = 0xFF;

        /* 去抖：按键引脚是否确实为低 */
        if (!(GPIO_IN & PIN_KEY0)) {
            btn_done = 1;
        }
        break;
    }

    default:
        break;
    }

    PLIC_CLAIM = src;
}


/* ================================================================
 * 初始化 — GPIO / Timer / PLIC
 * ================================================================ */
static void init_all(void)
{
    /* ---- GPIO ---- */
    GPIO_DIR  |=  (PL_LED0 | PL_LED1);   /* LED0/1 输出 */
    GPIO_SET(PL_LED1);                   /* LED1 常亮 */
    GPIO_CLR(PL_LED0);                   /* LED0 初始灭 */

    /* KEY0：输入 + 下降沿触发 + 中断使能 */
    GPIO_DIR      &= ~PIN_KEY0;
    GPIO_TR_TYPE  |=  PIN_KEY0;
    GPIO_TR_LVL0  |=  PIN_KEY0;
    GPIO_IRQ_ENA  |=  PIN_KEY0;

    /* ---- APB Timer：100MHz / 2000 / 1000 = 50Hz (20ms cycle) ---- */
    /*   实际上想要 ~500Hz 中断率 (2ms)：PSC=100, ARR=1999 → 500Hz   */
    TIM_PSC  = 100 - 1;                  /* 100MHz → 1MHz       */
    TIM_ARR  = 2000 - 1;                 /* 1MHz → 500Hz        */
    TIM_IER  = 0x03;                     /* UI 中断 + 溢出中断   */
    /* 先不开 PWM 模式（CCMR/CCER 保持默认 0） */
    TIM_CR   = 0x01;                     /* 启动定时器 */

    /* ---- PLIC ---- */
    PLIC_PRIORITY(PLIC_SRC_TIMER) = 5;   /* Timer 优先级 */
    PLIC_ENABLE |= (1 << PLIC_SRC_TIMER);

    PLIC_PRIORITY(PLIC_SRC_GPIO)  = 6;   /* GPIO 更高优先级 */
    PLIC_ENABLE |= (1 << PLIC_SRC_GPIO);

    PLIC_THRESHOLD = 0;                  /* 接收所有优先级 */

    /* ---- CPU 中断 ---- */
    core_enable_irq(MIE_MEIE);           /* 使能外部中断 */
    __enable_irq();                       /* 全局中断开 */
}


/* ================================================================
 * 切换到呼吸阶段：关 Timer ISR → 重配 PWM → 主循环控 PWM
 * ================================================================ */
static void switch_to_breath(void)
{
    phase = PHASE_BREATH;

    /* 关 LED0（停止闪烁） */
    GPIO_CLR(PL_LED0);

    /* 停止 Timer → 重配为 PWM 模式 */
    TIM_CR  = 0;

    /* Timer：100MHz / 100 / 1000 = 1kHz PWM 基频 */
    TIM_PSC  = 100 - 1;
    TIM_ARR  = 1000 - 1;
    TIM_CCMR = 0x01;              /* OC1: PWM mode 1                    */
    TIM_CCER = 0x01;              /* CC1 输出使能 → LED2(L15)            */
    TIM_IER  = 0x00;              /* 关闭所有中断                         */
    TIM_CR   = 0x01;              /* 重新启动                             */

    /* PLIC — GPIO 中断不再需要（可选保留以便再次按键） */
    /* 如果要关 GPIO 中断：GPIO_IRQ_ENA &= ~PIN_KEY0; */
}


/* ================================================================
 * 呼吸灯  —  线形爬升 + 下降 CCR1（0 ↔ ARR-1）
 * ================================================================ */
static void breath_loop(void)
{
    uint32_t ccr = 0;
    int      dir = 0;      /* 0=上升, 1=下降 */

    while (1) {
        delay_ms(BREATH_STEP_US / 1000);   /* 微秒→毫秒 */

        if (dir == 0) {
            if (ccr >= (TIM_ARR >> 1)) {   /* 爬升到一半 */
                dir = 1;
                ccr--;
            } else {
                ccr++;
            }
        } else {
            if (ccr == 0) {
                dir = 0;
                ccr++;
            } else {
                ccr--;
            }
        }
        TIM_CCR1 = ccr;
    }
}


/* ================================================================
 * main
 * ================================================================ */
int main(void)
{
    uart_init(115200);
    uart_puts("\r\n========================================\r\n");
    uart_puts(" BD32 综合中断测试\r\n");
    uart_puts(" 阶段 A: LED0 闪烁(500ms) LED1 常亮\r\n");
    uart_puts(" 按 KEY0 进入 阶段 B: LED2 呼吸\r\n");
    uart_puts("========================================\r\n\r\n");

    init_all();

    /* ---- 阶段 A：等按键 ---- */
    while (!btn_done) {
        __asm__ volatile("wfi");
    }
    uart_puts("按键触发！切换到呼吸灯阶段...\r\n");

    /* ---- 阶段 B：呼吸灯（永不退出）---- */
    switch_to_breath();
    breath_loop();

    return 0;
}
