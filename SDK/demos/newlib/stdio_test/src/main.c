/* printf 格式类型全覆盖测试 */
#include <stdio.h>
#include "bsp.h"

int main(void)
{
    uart_init(115200);
    char buf[128];

    uart_puts("=== printf format test ===\r\n");

    /* 整数 */
    sprintf(buf, "d=%d u=%u x=0x%x o=%o\r\n", 42, 42, 255, 255);
    uart_puts(buf);

    /* 字符和字符串 */
    sprintf(buf, "c='%c' s=\"%s\"\r\n", 'A', "hello");
    uart_puts(buf);

    /* 指针和百分号 */
    sprintf(buf, "p=%p %%\r\n", (void*)0x10000);
    uart_puts(buf);

    /* 宽度和对齐 */
    sprintf(buf, "[%8d] [%-8d] [%08d]\r\n", 123, 123, 123);
    uart_puts(buf);

    /* 负数 */
    sprintf(buf, "neg=%d neg_hex=0x%x\r\n", -42, -42);
    uart_puts(buf);

    /* long (ilp32 下 long=int, 但语法要通) */
    sprintf(buf, "ld=%ld lx=0x%lx\r\n", 123L, 0xABCL);
    uart_puts(buf);

    /* 混合多参数 */
    sprintf(buf, "%d + %d = %d, hex=%x, str=%s\r\n", 1, 2, 3, 0x10, "ok");
    uart_puts(buf);

    /* 定点小数 */
    printf("print_fixed: ");
    print_fixed(250, 2);                  /* 2.50 */
    printf(" ");
    print_fixed(-3141, 3);                /* -3.141 */
    printf("\r\nprint_fixed_scaled: ");
    print_fixed_scaled(244070559, 1000000); /* 244.070559 */
    printf(" ");
    print_fixed_scaled(250, 100);          /* 2.5 */
    printf("\r\n");

    uart_puts("PASS!\r\n");
    while (1);
    return 0;
}
