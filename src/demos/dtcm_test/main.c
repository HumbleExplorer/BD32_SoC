/*
 * DTCM 数据访问测试
 * 目的：验证 UART 下载后 DTCM 中的 .rodata/.data 能否正确访问
 *
 * 测试项：
 *   1. UART 基本发送（不依赖 DTCM）
 *   2. uart_puts 打印 .rodata 字符串常量
 *   3. uart_puthex 打印（内部用 static const hex[]，在 .rodata）
 *   4. 栈上字符串（栈在 DTCM 顶部）
 *   5. DTCM 基址直接读取验证（确认下载内容正确）
 */

#include "bd32.h"

/* .rodata 中的测试字符串 */
static const char test_str[] = "HELLO_DTCM_OK\n";

int main(void) {
    uart_init();

    /* === 测试1: 纯 UART 发送（不访问 DTCM 数据） === */
    uart_putc('T'); uart_putc('1'); uart_putc(':'); uart_putc(' ');
    uart_putc('O'); uart_putc('K'); uart_putc('\n');

    /* === 测试2: uart_puts 打印 .rodata 字符串 === */
    /* test_str 在 .rodata (DTCM 0x00020000+) */
    /* 如果 DTCM 数据不可读，这里会卡死或输出乱码 */
    uart_putc('T'); uart_putc('2'); uart_putc(':'); uart_putc(' ');
    uart_puts(test_str);

    /* === 测试3: uart_puthex 打印地址值 === */
    /* puthex 内部用了 static const hex[] = "012...DEF" (也在 .rodata) */
    /* 如果 puthex 输出正确 hex，说明 .rodata 至少部分可读 */
    uart_putc('T'); uart_putc('3'); uart_putc(':'); uart_putc(' ');
    uart_puthex((uint32_t)test_str);   /* 打印 test_str 的地址 */
    uart_putc('\n');

    /* === 测试4: 栈上字符串（栈在 DTCM 顶部 0x0002F000-） === */
    char stack_buf[32];
    stack_buf[0] = 'S'; stack_buf[1] = 'T'; stack_buf[2] = 'K';
    stack_buf[3] = '_'; stack_buf[4] = 'O';  stack_buf[5] = 'K';
    stack_buf[6] = '\n'; stack_buf[7] = '\0';
    uart_putc('T'); uart_putc('4'); uart_putc(':'); uart_putc(' ');
    uart_puts(stack_buf);

    /* === 测试5: 直接读 DTCM 基址处数据 === */
    /* .rodata 从 DTCM 基址 0x00020000 开始 */
    /* 逐字节读取打印，确认下载内容是否就是编译时的内容 */
    uart_putc('T'); uart_putc('5'); uart_putc(':'); uart_putc(' ');
    volatile unsigned char *ro = (volatile unsigned char *)0x00020000;
    for (int i = 0; i < 16; i++) {
        unsigned char b = ro[i];
        if (b >= 32 && b < 127)
            uart_putc((char)b);
        else
            uart_putc('.');
    }
    uart_putc('\n');

    /* === 测试6: 打印 .rodata 前 4 字 hex dump === */
    uart_putc('T'); uart_putc('6'); uart_putc(':'); uart_putc(' ');
    volatile unsigned int *row = (volatile unsigned int *)0x00020000;
    for (int i = 0; i < 4; i++) {
        uart_puthex(row[i]);
        uart_putc(' ');
    }
    uart_putc('\n');

    uart_puts("DONE\n");
    while (1);
}
