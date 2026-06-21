/* 测试数学函数 */
#include <stdio.h>
#include <math.h>
#include <stdlib.h>
#include "bsp.h"

int main(void)
{
    uart_init(115200);
    printf("\r\n=== math test ===\r\n");

    printf("abs(-5)=%d\r\n", abs(-5));

    double d = sqrt(9.0);
    printf("sqrt(9)=%d\r\n", (int)(d + 0.5));

    d = sin(0.0);
    printf("sin(0)=%d\r\n", (int)(d + 0.5));

    d = cos(0.0);
    printf("cos(0)=%d\r\n", (int)(d + 0.5));

    d = fabs(-3.14);
    printf("fabs(-3.14)=%d\r\n", (int)(d + 0.5));

    printf("PASS!\r\n");
    while (1);
    return 0;
}
