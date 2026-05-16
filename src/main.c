/* BD32 SoC — #include 单翻译单元 */
#include "../lib/bd32_printf.c"

int main(void) {
    *(volatile unsigned*)0xE001000C = 0x80;
    *(volatile unsigned*)0xE0010000 = 54;
    *(volatile unsigned*)0xE0010004 = 0;
    *(volatile unsigned*)0xE001000C = 0x03;

    printf("=%u=\n", 42);
    printf("=%u=\n", 99);

    unsigned a = 0, b = 1;
    for (unsigned i = 0; i < 20; i++) {
        printf("%u: %u\n", i, a);
        unsigned n = a + b; a = b; b = n;
    }

    while (1); return 0;
}
