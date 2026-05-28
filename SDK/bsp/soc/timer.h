/*
 * BD32 Timer — BD32 APB Timer 寄存器定义
 */
#ifndef TIMER_H
#define TIMER_H

#include <stdint.h>

#define TIMER_BASE       0xE0020000UL
#define TIM_PSC          (*(volatile uint32_t*)(TIMER_BASE + 0x00))
#define TIM_CNT          (*(volatile uint32_t*)(TIMER_BASE + 0x04))
#define TIM_ARR          (*(volatile uint32_t*)(TIMER_BASE + 0x08))
#define TIM_CR           (*(volatile uint32_t*)(TIMER_BASE + 0x0C))
#define TIM_IER          (*(volatile uint32_t*)(TIMER_BASE + 0x10))
#define TIM_SR           (*(volatile uint32_t*)(TIMER_BASE + 0x14))
#define TIM_CCMR         (*(volatile uint32_t*)(TIMER_BASE + 0x18))
#define TIM_CCER         (*(volatile uint32_t*)(TIMER_BASE + 0x1C))
#define TIM_CCR1         (*(volatile uint32_t*)(TIMER_BASE + 0x20))
#define TIM_CCR2         (*(volatile uint32_t*)(TIMER_BASE + 0x24))
#define TIM_CCR3         (*(volatile uint32_t*)(TIMER_BASE + 0x28))
#define TIM_CCR4         (*(volatile uint32_t*)(TIMER_BASE + 0x2C))

#define TIM_EN           (1 << 0)
#define TIM_CLR          (1 << 1)
#define TIM_DIR          (1 << 2)
#define TIM_OF_EN        (1 << 1)
#define TIM_OF_FLAG      (1 << 0)

#endif
