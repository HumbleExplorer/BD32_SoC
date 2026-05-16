/* 最精简中断测试：只验证 CLINT 中断 + GPIO[3] 翻转 */
static void putc(unsigned int c) {
    volatile unsigned int* lsr = (volatile unsigned int*)0xE0010014;
    while (!(*lsr & 0x20));
    volatile unsigned int* thr = (volatile unsigned int*)0xE0010000;
    *thr = c;
}

extern void clint_asm_set_timeout_ticks(unsigned int ticks);

void tmr_irq_handler(void) {
    /* 翻转 GPIO[3] + 重设 CLINT */
    volatile unsigned int* out = (volatile unsigned int*)0xE0000008;
    *out ^= 0x08;
    clint_asm_set_timeout_ticks(50000000);
}

int main(void) {
    volatile unsigned int* lcr = (volatile unsigned int*)0xE001000C;
    volatile unsigned int* dlm = (volatile unsigned int*)0xE0010004;
    volatile unsigned int* thr = (volatile unsigned int*)0xE0010000;
    *lcr = 0x80; *dlm = 0; *thr = 54; *lcr = 0x03;

    putc('O'); putc('K'); putc('\n');

    volatile unsigned int* dir = (volatile unsigned int*)0xE0000004;
    *dir = 0x08;      /* 只用 GPIO[3] */
    *(volatile unsigned int*)0xE0000008 = 0;

    clint_asm_set_timeout_ticks(50000000);

    __asm__ volatile("li t0, 0x80\n csrw mie, t0\n li t0, 0x1888\n csrw mstatus, t0");
    putc('E'); putc('N'); putc('\n');

    while (1);
}
