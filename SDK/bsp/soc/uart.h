/*
 * BD32 UART — BD32 UART16550 寄存器定义
 */
#ifndef UART_H
#define UART_H

#include <stdint.h>

#define UART_BASE        0xE0010000UL
#define UART_RBR_THR     (*(volatile uint32_t*)(UART_BASE + 0x00))
#define UART_DLL         (*(volatile uint32_t*)(UART_BASE + 0x00))
#define UART_DLM         (*(volatile uint32_t*)(UART_BASE + 0x04))
#define UART_IER         (*(volatile uint32_t*)(UART_BASE + 0x04))
#define UART_IIR         (*(volatile uint32_t*)(UART_BASE + 0x08))
#define UART_FCR         (*(volatile uint32_t*)(UART_BASE + 0x08))
#define UART_LCR         (*(volatile uint32_t*)(UART_BASE + 0x0C))
#define UART_MCR         (*(volatile uint32_t*)(UART_BASE + 0x10))
#define UART_LSR         (*(volatile uint32_t*)(UART_BASE + 0x14))
#define UART_MSR         (*(volatile uint32_t*)(UART_BASE + 0x18))

#define LSR_DR           (1 << 0)
#define LSR_THRE         (1 << 5)

#endif
