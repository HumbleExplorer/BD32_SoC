/*
 * Banner 调试版 — 逐步排查
 * 原版 banner 不打印 → 逐步加回功能定位问题
 */

#include "bd32.h"

/* 必进 .data — 不是 const，有初始值 */
unsigned int data_val = 0xA5A5A5A5;

int main(void) {
    uart_init();

    /* 测试A: 只用 BSP 的 uart_putc — 验证基础功能 */
    uart_putc('A'); uart_putc(':'); uart_putc('O'); uart_putc('K');
    uart_putc('\n');

    /* 测试B: 打印 data_val 的地址（不读它的值，只打地址） */
    uart_putc('B'); uart_putc(':'); uart_putc(' ');
    uart_puthex((uint32_t)&data_val);
    uart_putc('\n');

    /* 测试C: 读取并打印 data_val 的值 */
    uart_putc('C'); uart_putc(':'); uart_putc(' ');
    uart_puthex(data_val);
    uart_putc('\n');

    /* 测试D: 直接读 DTCM 基址前几个字 */
    uart_putc('D'); uart_putc(':'); uart_putc(' ');
    volatile unsigned int *dtcm = (volatile unsigned int *)0x00020000;
    uart_puthex(dtcm[0]); uart_putc(' ');
    uart_puthex(dtcm[4]); uart_putc(' ');
    uart_puthex(dtcm[5]); uart_putc(' ');
    uart_puthex(dtcm[6]);  /* data_val 应该在 word 6 (offset 0x18) */
    uart_putc('\n');

    uart_puts("DONE\n");
    while (1);
}
