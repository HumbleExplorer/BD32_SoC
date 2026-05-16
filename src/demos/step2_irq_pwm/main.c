/*
 * Step 2 — 修正中断初始化顺序 + 寄存器诊断打印
 */
#include "bd32.h"
#include "bd32_core.h"

#define INT_TIMER 3

static volatile uint32_t led_on;

/* hex 打印 */
static void phex(uint32_t v) {
    for (int i = 28; i >= 0; i -= 4) {
        int d = (v >> i) & 0xF;
        uart_putc(d < 10 ? '0' + d : 'A' + d - 10);
    }
}

void ext_irq_handler(void) {
    uint32_t src = PLIC_CLAIM;
    if (src != INT_TIMER) { PLIC_COMPLETE = src; return; }
    TIM_SR = TIM_OF_FLAG;

    led_on ^= 1;
    if (led_on) GPIO_SET(PIN_LED0);
    else        GPIO_CLR(PIN_LED0);
    PLIC_COMPLETE = src;
}

int main(void) {
    uart_init();
    uart_puts("Step2\n");
    // uart_puts("Test1\n");
    GPIO_DIR |= PIN_LED0;
    // uart_puts("Test2\n");
    GPIO_CLR(PIN_LED0);
    uart_puts("Test3\n");
    TIM_PSC = 999;
    TIM_ARR = 999;
    TIM_CCMR = 0x01;
    TIM_CCER = 0x01;
    TIM_CR  = 0x01;
    TIM_IER = 0x03;
    uart_puts("Test4\n");
    /* 第二步：配置 PLIC */
    PLIC_PRIORITY(INT_TIMER) = 1;
    PLIC_ENABLE |= (1 << INT_TIMER);
    PLIC_THRESHOLD = 0;

    uart_puts("Test5\n");
    /* 第四步：开中断（mie + mstatus） */
    set_csr(mie, MIE_MEIE);
    set_csr(mstatus, MSTATUS_MIE);
    PLIC_COMPLETE = INT_TIMER;
    
    uart_puts("R:\n");
    uart_puts("PSC="); phex(TIM_PSC); uart_puts("\n");
    uart_puts("ARR="); phex(TIM_ARR); uart_puts("\n");
    uart_puts("CNT="); phex(TIM_CNT); uart_puts("\n");
    uart_puts("CR=");  phex(TIM_CR);  uart_puts("\n");
    uart_puts("CCMR=");phex(TIM_CCMR);uart_puts("\n");
    uart_puts("CCER=");phex(TIM_CCER);uart_puts("\n");
    uart_puts("CCR1=");phex(TIM_CCR1);uart_puts("\n");
    uart_puts("IER="); phex(TIM_IER); uart_puts("\n");
    uart_puts("SR=");  phex(TIM_SR);  uart_puts("\n");
    uart_puts("PLIP=");phex(PLIC_PRIORITY(3)); uart_puts("\n");
    uart_puts("PLIE=");phex(PLIC_ENABLE);      uart_puts("\n");
    uart_puts("PLIT=");phex(PLIC_THRESHOLD);   uart_puts("\n");
    uart_puts("mip="); phex(read_csr(mip));    uart_puts("\n");
    uart_puts("mie="); phex(read_csr(mie));    uart_puts("\n");
    uart_puts("mst="); phex(read_csr(mstatus));uart_puts("\n");
    /* 呼吸 + 闪烁 */
    uint32_t ccr = 0, dir = 0, cnt = 0;
    while (1) {
        clint_delay_ms(2);

        if (dir == 0) {
            if (ccr >= 999) { dir = 1; ccr--; }
            else ccr++;
        } else {
            if (ccr == 0) { dir = 0; ccr++; }
            else ccr--;
        }
        TIM_CCR1 = ccr;

        cnt++;
        if (cnt >= 500) {
            cnt = 0;
            uart_putc('M'); phex(read_csr(mip));
            uart_putc('P'); phex(PLIC_CLAIM); PLIC_COMPLETE = INT_TIMER;
            uart_putc('\n');
        }
    }
}
