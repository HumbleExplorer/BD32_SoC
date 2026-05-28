/*
 * BD32 GPIO — BD32 GPIO 寄存器定义
 */
#ifndef GPIO_H
#define GPIO_H

#include <stdint.h>

#define GPIO_BASE        0xE0000000UL
#define GPIO_DATA        (*(volatile uint32_t*)(GPIO_BASE + 0x00))
#define GPIO_DIR         (*(volatile uint32_t*)(GPIO_BASE + 0x04))
#define GPIO_OUT         (*(volatile uint32_t*)(GPIO_BASE + 0x08))
#define GPIO_IN          (*(volatile uint32_t*)(GPIO_BASE + 0x0C))
#define GPIO_BOP_SET     (*(volatile uint32_t*)(GPIO_BASE + 0x24))
#define GPIO_BOP_CLR     (*(volatile uint32_t*)(GPIO_BASE + 0x28))

#define GPIO_TR_TYPE     (*(volatile uint32_t*)(GPIO_BASE + 0x10))
#define GPIO_TR_LVL0     (*(volatile uint32_t*)(GPIO_BASE + 0x14))
#define GPIO_TR_LVL1     (*(volatile uint32_t*)(GPIO_BASE + 0x18))
#define GPIO_TR_STAT     (*(volatile uint32_t*)(GPIO_BASE + 0x1C))
#define GPIO_IRQ_ENA     (*(volatile uint32_t*)(GPIO_BASE + 0x20))

#define GPIO_SET(bits)   (GPIO_BOP_SET = (uint32_t)(bits))
#define GPIO_CLR(bits)   (GPIO_BOP_CLR = (uint32_t)(bits))

#endif
