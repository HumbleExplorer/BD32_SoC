/* 测试类型转换 + malloc */
#include <stdio.h>
#include <stdlib.h>
#include "bsp.h"

int main(void)
{
    uart_init(115200);
    printf("\r\n=== stdlib test ===\r\n");

    printf("atoi(123)=%d\r\n", atoi("123"));
    printf("strtol(FF)=%d\r\n", (int)strtol("0xFF", NULL, 16));
    printf("abs(-7)=%d\r\n", abs(-7));

    void *p = malloc(128);
    printf("malloc=%s\r\n", p ? "ok" : "fail");
    free(p);

    p = calloc(10, 4);
    printf("calloc=%s\r\n", p ? "ok" : "fail");
    free(p);
    printf("PASS!\r\n");
    while (1);
    return 0;
}
