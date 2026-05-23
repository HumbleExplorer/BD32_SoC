/*
 * BD32 APB 定时器驱动
 * 参考 Panda apb_timer / SparrowRV timer / riscv-mcu timer
 */

#ifndef BD32_TIMER_H
#define BD32_TIMER_H

#include "bd32.h"

/* 初始化定时器 (溢出周期 = (PSC+1) * (ARR+1) 时钟周期) */
static inline void timer_init(uint32_t psc, uint32_t arr) {
    TIM_PSC = psc;
    TIM_ARR = arr;
}

/* 启动定时器 */
static inline void timer_start(void) {
    TIM_CR = TIM_EN;
}

/* 停止定时器 */
static inline void timer_stop(void) {
    TIM_CR = 0;
}

/* 使能溢出中断 */
static inline void timer_enable_irq(void) {
    TIM_IER |= TIM_OF_EN;
}

/* 获取中断状态 */
static inline uint32_t timer_get_status(void) {
    return TIM_SR;
}

/* 清除溢出标志 */
static inline void timer_clear_flag(void) {
    TIM_SR = TIM_OF_FLAG;
}

/* 等待溢出（轮询） */
static inline void timer_wait_overflow(void) {
    while (!(TIM_SR & TIM_OF_FLAG));
    TIM_SR = TIM_OF_FLAG;
}

#endif /* BD32_TIMER_H */
