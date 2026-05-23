/*
 * NMSIS SOC — BD32 SoC 顶层统一头文件
 * 包含所有外设定义和系统参数
 */
#ifndef NMSIS_SOC_H
#define NMSIS_SOC_H

#include "nmsis_core.h"
#include "nmsis_gpio.h"
#include "nmsis_uart.h"
#include "nmsis_timer.h"
#include "nmsis_clint.h"
#include "nmsis_plic.h"

/* 系统时钟 */
#define CPU_FREQ_HZ      100000000UL
#define CPU_FREQ_KHZ     (CPU_FREQ_HZ / 1000UL)

#endif
