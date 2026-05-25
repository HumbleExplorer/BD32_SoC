/* 测试字符串操作 */
#include <stdio.h>
#include <string.h>
#include "bsp.h"

int main(void)
{
    uart_init();
    printf("\r\n=== string test ===\r\n");

    printf("strlen=%d\r\n", (int)strlen("hello"));
    char dst[16];
    strcpy(dst, "copyok");
    printf("strcpy=%s\r\n", dst);
    memset(dst, 0, 16);
    memcpy(dst, "memcpy", 6);
    printf("memcpy=%s\r\n", dst);
    printf("strchr=%d\r\n", strchr("abc", 'b') ? 1 : 0);
    printf("strstr=%d\r\n", strstr("hello world", "world") ? 1 : 0);
    printf("PASS!\r\n");
    while (1);
    return 0;
}
