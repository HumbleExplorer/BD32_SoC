/* Demo — UART */
#include "demo.h"

void uart_init(void) {
    volatile unsigned int* lcr = (volatile unsigned int*)0xE001000C;
    volatile unsigned int* dlm = (volatile unsigned int*)0xE0010004;
    volatile unsigned int* thr = (volatile unsigned int*)0xE0010000;
    *lcr = 0x80;
    *dlm = 0;
    *thr = 54;
    *lcr = 0x03;
}

void uart_putc(char c) {
    volatile unsigned int* lsr = (volatile unsigned int*)0xE0010014;
    volatile unsigned int* thr = (volatile unsigned int*)0xE0010000;
    while (!(*lsr & 0x20));
    *thr = (unsigned int)(unsigned char)c;
}
