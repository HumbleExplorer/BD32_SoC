/*
 * BD32 GPIO 驱动
 * 参考 Panda apb_gpio / tinyriscv gpio / nuclei-sdk gd32vf103_gpio
 */

#ifndef BD32_GPIO_H
#define BD32_GPIO_H

#include "bd32.h"

/* ── 方向 ── */
static inline void gpio_set_dir(uint32_t dir)   { GPIO_DIR = dir; }

/* ── 全字读写（非原子，仅初始化阶段用） ── */
static inline void gpio_write(uint32_t val)     { GPIO_OUT = val; }
static inline uint32_t gpio_read(void)          { return GPIO_IN; }
static inline void gpio_toggle(uint32_t mask)   { GPIO_OUT ^= mask; }

/* ── 原子位操作（基于 BOP 寄存器，ISR 安全） ── */
static inline void gpio_set(uint32_t bits)      { GPIO_SET(bits); }
static inline void gpio_clr(uint32_t bits)      { GPIO_CLR(bits); }

/* ── 中断控制 ── */

/** 使能指定引脚的中断（先配触发模式再使能） */
static inline void gpio_enable_irq(uint32_t mask) {
    GPIO_IRQ_ENA |= mask;
}

/** 除能指定引脚的中断 */
static inline void gpio_disable_irq(uint32_t mask) {
    GPIO_IRQ_ENA &= ~mask;
}

/** 清除中断标志（写 1 清除） */
static inline void gpio_clear_irq_flag(uint32_t mask) {
    GPIO_TR_STAT = mask;
}

/** 获取中断状态 */
static inline uint32_t gpio_get_irq_status(void) {
    return GPIO_TR_STAT;
}

/**
 * 配置中断触发模式
 * @param pin    GPIO 引脚编号
 * @param mode   0=低电平, 1=高电平, 2=下降沿, 3=上升沿
 */
static inline void gpio_set_irq_trigger(uint32_t pin, int mode) {
    uint32_t m = (1u << pin);
    switch (mode) {
    case 0: /* 低电平 */
        GPIO_TR_TYPE    &= ~m;
        GPIO_TR_LVL0    |=  m;
        GPIO_TR_LVL1    &= ~m;
        break;
    case 1: /* 高电平 */
        GPIO_TR_TYPE    &= ~m;
        GPIO_TR_LVL0    &= ~m;
        GPIO_TR_LVL1    |=  m;
        break;
    case 2: /* 下降沿 */
        GPIO_TR_TYPE    |=  m;
        GPIO_TR_LVL0    |=  m;
        GPIO_TR_LVL1    &= ~m;
        break;
    case 3: /* 上升沿 */
        GPIO_TR_TYPE    |=  m;
        GPIO_TR_LVL0    &= ~m;
        GPIO_TR_LVL1    |=  m;
        break;
    }
}

#endif /* BD32_GPIO_H */
