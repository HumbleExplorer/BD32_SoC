/*
 * BD32 PLIC — BD32 平台级中断控制器寄存器定义
 */
#ifndef PLIC_H
#define PLIC_H

#include <stdint.h>

#define PLIC_BASE        0xFC000000UL
#define PLIC_PRIORITY(id) (*(volatile uint32_t*)(PLIC_BASE + 4*(id)))
#define PLIC_PENDING      (*(volatile uint32_t*)(PLIC_BASE + 0x1000))
#define PLIC_ENABLE       (*(volatile uint32_t*)(PLIC_BASE + 0x2000))
#define PLIC_THRESHOLD    (*(volatile uint32_t*)(PLIC_BASE + 0x2080))
#define PLIC_CLAIM        (*(volatile uint32_t*)(PLIC_BASE + 0x2084))
#define PLIC_COMPLETE     PLIC_CLAIM

#endif
