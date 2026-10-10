/*
 * UART IRQ Demo — UART 中断收发（PLIC 源 1）
 *
 * RX：RDA 中断（FCR 水位=1，每字节一个中断），ISR 读 RBR 取数（读即清）压入接收环
 * TX：THRE 中断驱动，主循环投递整行后开 IER.THRE；ISR 读 IIR（清）后从发送环
 *     取一字节写 THR，发送环空则关 IER.THRE 停发
 * 回显 3 行后写 GPIO 签名 0xA5 并打印 PASS
 *
 * 中断收尾顺序与 PLIC 契约一致：处理事件 → 读状态寄存器清中断源 → Complete
 */
#include "bsp.h"

#define PLIC_SRC_UART 1

#define RX_BUF_LEN  64
#define TX_BUF_LEN  64
#define ECHO_LINES  3

/* 环形缓冲：单生产者单消费者，头尾各归一方写，volatile 即可无锁 */
static volatile char rx_buf[RX_BUF_LEN];
static volatile uint32_t rx_head = 0;           /* 仅 ISR 写 */
static volatile uint32_t rx_tail = 0;           /* 仅主循环写 */

static volatile char tx_buf[TX_BUF_LEN];
static volatile uint32_t tx_head = 0;           /* 仅主循环写 */
static volatile uint32_t tx_tail = 0;           /* 仅 ISR 写 */

static volatile uint32_t rx_overflow = 0;

#define IIR_NO_INT   0xC1
#define IIR_MODE(x)  ((x) & 0x0F)
#define IIR_MSR      0x00
#define IIR_THRE     0x02
#define IIR_RLS      0x06
#define IIR_RDA      0x04
#define IIR_TOUT     0x0C

#define LSR_TEMT     (1 << 6)
#define IER_RDA      0x01
#define IER_THRE     0x02

/* 外部中断入口（覆盖 trap_handler.c 弱定义） */
void ext_irq_handler(void)
{
    uint32_t claim = PLIC_CLAIM;

    if (claim == PLIC_SRC_UART) {
        uint32_t iir = UART_IIR;
        switch (IIR_MODE(iir)) {
        case IIR_RDA:
        case IIR_TOUT:
            /* 读 RBR 即清 RDA/超时中断；按 LSR.DR 排空 FIFO */
            while (UART_LSR & LSR_DR) {
                uint32_t next = (rx_head + 1) % RX_BUF_LEN;
                char c = (char)(UART_RBR_THR & 0xFF);
                if (next != rx_tail) {
                    rx_buf[rx_head] = c;
                    rx_head = next;
                } else {
                    rx_overflow++;
                }
            }
            break;
        case IIR_THRE:
            /* 读 IIR 已清本拍 THRE 中断；发送环空则关 THRE 停发 */
            if (tx_tail != tx_head) {
                UART_RBR_THR = (uint32_t)(uint8_t)tx_buf[tx_tail];
                tx_tail = (tx_tail + 1) % TX_BUF_LEN;
            } else {
                UART_IER &= ~IER_THRE;
            }
            break;
        case IIR_RLS:
            (void)UART_LSR;                 /* 读 LSR 清线状态中断 */
            break;
        case IIR_MSR:
            (void)UART_MSR;                 /* 读 MSR 清调制解调器中断 */
            break;
        default:
            break;                          /* IIR_NO_INT：无悬挂子源 */
        }
    }
    if (claim)
        PLIC_CLAIM = claim;                 /* Complete：电平 gateway 重开 */
}

/* 主循环投递一行到发送环，末尾统一开发送中断（避免空环假唤醒） */
static void tx_submit(const char *s)
{
    while (*s) {
        uint32_t next = (tx_head + 1) % TX_BUF_LEN;
        while (next == tx_tail)             /* 环满等待：ISR 消费腾空间 */
            ;
        tx_buf[tx_head] = *s++;
        tx_head = next;
    }
    __disable_irq();
    UART_IER |= IER_THRE;
    __enable_irq();
}

int main(void)
{
    char line[RX_BUF_LEN];
    static char echo[RX_BUF_LEN + 8];
    uint32_t len = 0;
    uint32_t lines = 0;

    uart_init(115200);
    uart_puts("\r\nBD32 UART IRQ - type 3 lines, each echoed\r\n");

    /* FCR 复位 0xC0（水位 14），改水位=1：每字节即触发 RDA */
    UART_FCR = 0x01;
    UART_IER = IER_RDA;

    /* PLIC：UART 源 1，优先级 1，门限 0 */
    PLIC_PRIORITY(PLIC_SRC_UART) = 1;
    PLIC_ENABLE |= (1u << PLIC_SRC_UART);
    PLIC_THRESHOLD = 0;

    core_enable_irq(MIE_MEIE);
    __enable_irq();

    while (lines < ECHO_LINES) {
        /* 取收到的字节（'\r' 结束一行，'\n' 丢弃） */
        while (rx_tail != rx_head) {
            char c = rx_buf[rx_tail];
            rx_tail = (rx_tail + 1) % RX_BUF_LEN;
            if (c == '\r') {
                uint32_t i = 0, j = 0;
                line[len] = 0;
                echo[i++] = 'r'; echo[i++] = 'x';
                echo[i++] = (char)('0' + lines + 1);
                echo[i++] = ':';
                for (j = 0; j < len; j++)
                    echo[i++] = line[j];
                echo[i++] = '\r'; echo[i++] = '\n'; echo[i] = 0;
                len = 0;
                lines++;
                tx_submit(echo);
            } else if (c != '\n' && len < RX_BUF_LEN - 1) {
                line[len++] = c;
            }
        }
        __asm__ volatile("wfi");
    }

    /* 等发送彻底排空（发送环空 + 移位寄存器空）再打签名 */
    while (tx_tail != tx_head)
        ;
    while (!(UART_LSR & LSR_TEMT))
        ;

    GPIO_DIR |= 0x20;
    GPIO_OUT = 0xA5;                        /* TB 判定签名 */
    uart_puts("\r\nPASS!\r\n");
    while (1)
        ;
    return 0;
}
