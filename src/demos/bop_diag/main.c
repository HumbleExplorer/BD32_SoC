/* Test: PLIC 外部中断 + GPIO LED */
#include "bd32.h"
#include "bd32_core.h"
#include "bd32_gpio.h"

#define INT_TIMER 3
static volatile uint32_t irq_count;

void ext_irq_handler(void) {
    uint32_t src = PLIC_CLAIM;
    if (src != INT_TIMER) { PLIC_COMPLETE = src; return; }
    TIM_SR = TIM_OF_FLAG;
    irq_count++;
    PLIC_COMPLETE = src;
}

int main(void) {
    uart_init();
    uart_puts("TPL\n");

    gpio_set_dir(PIN_LED0);
    gpio_clr(PIN_LED0);

    /* Timer: 不配通道，只用溢出中断 */
    volatile uint32_t * const t = (volatile uint32_t *)0xE0020000;
    t[0] = 199;   uart_puts("PSC\n");
    t[2] = 999;   uart_puts("ARR\n");
    t[1] = 0;     uart_puts("CNT\n");
    t[4] = 0x03;  uart_puts("IER\n");  /* 使能溢出中断 */

    PLIC_PRIORITY(3) = 1;        uart_puts("PRI\n");
    PLIC_ENABLE |= (1 << 3);     uart_puts("ENA\n");
    PLIC_THRESHOLD = 0;          uart_puts("THR\n");

    TIM_SR = 1;                  uart_puts("CLR\n");
    (void)PLIC_CLAIM;            uart_puts("CLM\n");
    PLIC_COMPLETE = 3;           uart_puts("CMP\n");

    set_csr(mie, MIE_MEIE);      uart_puts("MIE\n");
    set_csr(mstatus, MSTATUS_MIE); uart_puts("MIE2\n");
    t[3] = 1;                    uart_puts("GO\n");

    uint32_t last = 0;
    while (1) {
        clint_delay_ms(500);
        if (irq_count != last) {
            last = irq_count;
            gpio_toggle(PIN_LED0);
            uart_putc('I');
        }
        uart_putc('.');
    }
}
