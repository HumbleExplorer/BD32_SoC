/* Demo — GPIO + 延时 */
#include "demo.h"

void gpio_off(void) {
    volatile unsigned int* dir = (volatile unsigned int*)0xE0000004;
    volatile unsigned int* out = (volatile unsigned int*)0xE0000008;
    *dir = 0x18;
    *out = 0;
}

void delay_loop(int n) {
    while (n--) {
        volatile int i;
        for (i = 0; i < 100; i++);
    }
}
