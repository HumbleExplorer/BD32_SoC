/*
 * Demo: Hello World — 使用 printf（newlib-nano）
 * 验证：printf 输出 / malloc 堆分配
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "bsp.h"

int main(void)
{
    uart_init();

    printf("\r\nBD32 Hello World (newlib-nano)\r\n");
    printf("Printf works! sizeof(int)=%d\r\n", (int)sizeof(int));

    char *buf = malloc(64);
    if (buf) {
        strcpy(buf, "Malloc + strcpy works!");
        printf("%s\r\n", buf);
        free(buf);
    } else {
        printf("malloc failed!\r\n");
    }

    printf("PASS!\r\n");
    while (1);
    return 0;
}
