/*
 * BD32 CLINT — BD32 核内局部中断控制器寄存器定义
 */
#ifndef CLINT_H
#define CLINT_H

#include <stdint.h>

#define CLINT_BASE       0xF2000000UL
#define CLINT_MSIP       (*(volatile uint32_t*)(CLINT_BASE + 0x0000))
#define CLINT_MTIME_LO   (*(volatile uint32_t*)(CLINT_BASE + 0xBFF8))
#define CLINT_MTIME_HI   (*(volatile uint32_t*)(CLINT_BASE + 0xBFFC))
#define CLINT_MTIMECMP_LO (*(volatile uint32_t*)(CLINT_BASE + 0x4000))
#define CLINT_MTIMECMP_HI (*(volatile uint32_t*)(CLINT_BASE + 0x4004))

/* 寄存器地址（用于指针引用） */
#define CLINT_MTIME_LO_ADDR   (CLINT_BASE + 0xBFF8)
#define CLINT_MTIME_HI_ADDR   (CLINT_BASE + 0xBFFC)

#endif
