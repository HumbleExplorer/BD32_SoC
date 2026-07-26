/*
 * Demo: Bus Timeout — 总线访问超时异常测试
 *
 * 测试目标：
 *   验证总线超时保护机制。当某个 APB 从机挂死（PREADY 永不拉高）时，
 *   APB_Master 在 BUS_TIMEOUT/2 个时钟后强制完成并返回 SLVERR；
 *   若桥也未恢复，AXI_Lite_Master 在 BUS_TIMEOUT 个时钟后返回 DECERR。
 *   CPU 将两者均转为 load/store access fault，跳入异常处理，
 *   而不是永久卡死在 ~bus_ready 等待里。
 *
 * 测试流程：
 *   1. main 向 Timer (0xE0020000) 写一个寄存器。
 *   2. 仿真台在下载完成后 force apb_pready[4]=0，使 Timer 挂死。
 *   3. 该 store 在总线上得不到响应 → APB 桥超时返回 SLVERR →
 *      触发 store access fault (mcause=7)，跳入 serr_handler。
 *   4. serr_handler 把 mcause / 原始 mepc 记录到固定 DTCM 地址，
 *      并把 mepc+4 写回（跳过故障指令），然后返回。
 *   5. main 继续执行，向 GPIO 写 PASS 签名，进入死循环。
 *
 * 仿真台判定：
 *   - DTCM[0x28000] == 7            (store access fault)
 *   - DTCM[0x28004] == 故障 store 指令地址 (在 ITCM 范围内)
 *   - GPIO_OUT      == 0x05         (PASS 签名，刻意避开 BootROM 的 0x18)
 */
#include "bsp.h"

/* 固定 DTCM 暂存地址：位于 heap 末端(~0x25000)与栈基址(0x2F000)之间的安全空隙，
 * 避免与 .data/.bss/.heap/.stack 任何链接布局冲突 */
#define RECORD_MCAUSE_ADDR  0x00028000UL
#define RECORD_MEPC_ADDR    0x00028004UL
#define RECORD_DONE_ADDR    0x00028008UL

#define PASS_SIGNATURE      0x05u   /* GPIO[2]|[0] — 刻意避开 BootROM 会写的 0x18(LED0|LED1) */

/* 覆盖弱定义异常处理函数 */
void serr_handler(uint32_t mcause, uint32_t mepc)
{
    *(volatile uint32_t*)RECORD_MCAUSE_ADDR = mcause;
    *(volatile uint32_t*)RECORD_MEPC_ADDR   = mepc;
    *(volatile uint32_t*)RECORD_DONE_ADDR   = 0xA5A5A5A5u;

    /* 跳过故障指令（store 为 4 字节），避免 mret 后再次触发同一异常 */
    __asm__ volatile("csrw mepc, %0" :: "r"(mepc + 4));
}

int main(void)
{
    uart_init(115200);
    uart_puts("\r\nBD32 Bus Timeout Test\r\n");

    /* 配置 LED0/LED1 为输出（GPIO 正常，不会挂死） */
    GPIO_DIR |= LED_MASK;
    GPIO_OUT &= ~LED_MASK;

    uart_puts("Writing to Timer (will hang bus)...\r\n");

    /* 触发总线访问：若 Timer 从机被仿真台挂死，此处将触发 store access fault */
    TIM_PSC = 0x1234;

    /* 异常处理跳过上面的 store 后，执行流到达这里 */
    uart_puts("Returned from exception. PASS\r\n");
    GPIO_OUT = PASS_SIGNATURE;

    while (1);
    return 0;
}
