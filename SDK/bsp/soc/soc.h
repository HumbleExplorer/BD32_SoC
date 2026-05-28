/*
 * BD32 SOC — BD32 SoC 顶层统一头文件
 * 包含所有外设定义和系统参数
 */
#ifndef SOC_H
#define SOC_H

#include "core.h"
#include "gpio.h"
#include "uart.h"
#include "timer.h"
#include "clint.h"
#include "plic.h"

/* 系统时钟 */
#define CPU_FREQ_HZ      100000000UL
#define CPU_FREQ_KHZ     (CPU_FREQ_HZ / 1000UL)

#endif
