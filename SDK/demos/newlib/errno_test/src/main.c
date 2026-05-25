/* 测试 errno */
#include <stdio.h>
#include <errno.h>
#include "bsp.h"

int main(void)
{
    uart_init();
    printf("\r\n=== errno test ===\r\n");

    errno = 0;
    printf("errno init=%d\r\n", errno);

    errno = ENOMEM;
    printf("errno set=%d\r\n", errno);

    printf("PASS!\r\n");
    while (1);
    return 0;
}
