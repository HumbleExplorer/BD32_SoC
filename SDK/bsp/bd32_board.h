/*
 * BD32 Board — 板级定义（LED、时钟、外设选通）
 * 不能放 NMSIS——NMSIS 是芯片级寄存器定义，与板子无关
 */
#ifndef BD32_BOARD_H
#define BD32_BOARD_H

/* 板载 LED */
#define PIN_LED0         (1 << 3) /* H15 */
#define PIN_LED1         (1 << 4) /* J16 */
#define LED_MASK         (PIN_LED0 | PIN_LED1)

/* 按键 */
#define PIN_BTN0         (1 << 0)
#define PIN_KEY0         (1 << 1)  /* L14 */
#define PIN_KEY1         (1 << 2)  /* K16 */

#endif
