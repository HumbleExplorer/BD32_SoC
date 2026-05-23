/*
 * 最小仿真调试程序 — GPIO 边沿中断 + PLIC
 * 仿真观测: external_int / mip.MEIP / mtvec 跳转
 */
#include "bsp.h"

static volatile int cnt = 0;

void ext_irq_handler(void)
{
    uint32_t claim = PLIC_CLAIM;
    if (claim == 2) {
        GPIO_TR_STAT = 0x02;
        cnt++;
    }
    PLIC_CLAIM = claim;
}

int main(void)
{
    GPIO_DIR &= ~PIN_KEY0;

    GPIO_TR_TYPE |= PIN_KEY0;      /* edge */
    GPIO_TR_LVL0 |= PIN_KEY0;      /* falling */
    GPIO_IRQ_ENA |= PIN_KEY0;

    PLIC_PRIORITY(2) = 3;
    PLIC_ENABLE |= (1 << 2);
    PLIC_THRESHOLD = 0;

    core_enable_irq(MIE_MEIE);
    __enable_irq();

    while (cnt < 3);
    while (1);
}
