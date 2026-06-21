/*
 * Demo: Empty — 最小裸金属启动（无 C 标准库）
 * 验证：CPU 启动 + UART 输出 → 最小闭环
 */
#include "bsp.h"

int main(void)
{
    uart_init(115200);
    uart_puts("\r\nBD32 Empty Demo - OK!\r\n");
    while (1);
    return 0;
}
