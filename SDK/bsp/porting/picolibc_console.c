/*
 * picolibc_console.c — picolibc 标准 I/O 控制台适配
 *
 * picolibc 的 tinystdio 通过 FILE 对象输出，应用需自行提供
 * stdin/stdout/stderr 三个指针。这里统一指向一个 putc 直通
 * UART 的 FILE，printf/puts/putchar 即可直接使用。
 */
#include <stdio.h>
#include "bsp.h"

static int console_putc(char c, FILE *file)
{
    (void)file;
    uart_putc(c);
    return c;
}

static FILE __console_stdio = FDEV_SETUP_STREAM(console_putc, NULL, NULL,
                                                _FDEV_SETUP_WRITE);

FILE *const stdin  = &__console_stdio;
FILE *const stdout = &__console_stdio;
FILE *const stderr = &__console_stdio;
