/*
 * printf_fixed.c — 利用 printf 打印定点小数
 */
#include <stdio.h>
#include <stdint.h>

/* 打印定点小数：val 是放大 10^precision 倍的值
 * 例: print_fixed(250, 2)  → "2.50"
 *     print_fixed(-3141, 3) → "-3.141"
 */
void print_fixed(int32_t val, int precision)
{
    if (val < 0) { putchar('-'); val = -val; }

    int32_t divisor = 1;
    for (int i = 0; i < precision; i++) divisor *= 10;

    printf("%d", (int)(val / divisor));

    if (precision > 0) {
        putchar('.');
        uint32_t frac = (uint32_t)(val % divisor);
        uint32_t d = divisor / 10;
        while (d) {
            putchar('0' + (frac / d) % 10);
            d /= 10;
        }
    }
}

/* 自动定点：val/scale，输出所有有效小数位
 * 例: print_fixed_scaled(244070559, 1000000) → "244.070559"
 *     print_fixed_scaled(250, 100)           → "2.5"（无尾部零）
 */
void print_fixed_scaled(int32_t val, int32_t scale)
{
    if (scale <= 0) return;
    if (val < 0) { putchar('-'); val = -val; }

    printf("%d", val / scale);

    uint32_t rem = (uint32_t)(val % scale);
    if (rem) {
        putchar('.');
        while (rem) {
            rem *= 10;
            putchar('0' + (rem / scale) % 10);
            rem %= scale;
        }
    }
}
