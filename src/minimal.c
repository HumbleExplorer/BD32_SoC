/*
 * BD32 SoC DTCM 下载验证程序（最小版本）
 * 仅验证 DTCM 数据能通过 uart_download 正确写入
 * 使用了 .rodata 中的字符串（测试 DTCM 下载）
 */

#include "periph.h"

/* 这些字符串在 .rodata 段中，通过 uart_download 写入 DTCM */
static const char msg_boot[] = "\r\nBD32 DTCM Download OK!\r\n";
static const char msg_blink[] = "LED blinking...\r\n";

int main(void) {
    uart_init();
    gpio_init();
    timer_init();

    /* 打印 DTCM 中的字符串 —— 验证 DTCM 下载 */
    uart_puts(msg_boot);

    /* 循环闪烁 LED */
    while (1) {
        timer_wait_overflow();
        gpio_toggle(LED0 | LED2);
    }

    return 0;
}
