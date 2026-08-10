# 外设编程指南

所有外设挂载于 APB 总线（经 AXI-APB 桥），寄存器按 32-bit 字访问，地址以
SoC 配置宏为准（见 `rtl/SoC_Config.sv` 与 `rtl/Bus/APB_Interconnect.sv`）。
驱动代码参考 `SDK/bsp/drivers/`，demo 见 `SDK/demos/`。

## 地址映射

| 外设 | 基地址 | PSEL |
|---|---|---|
| CLINT | 0xF200_0000 | 0 |
| PLIC | 0xFC00_0000 | 1 |
| GPIO | 0xE000_0000 | 2 |
| UART | 0xE001_0000 | 3 |
| Timer | 0xE002_0000 | 4 |
| SPI / I2C | 0xE003_0000 / 0xE004_0000 | 5/6（预留，未实现） |

## GPIO（apb_gpio.sv）

支持推挽/开漏两种输出模式；每个引脚独立配置输入/输出方向；支持电平触发与
边沿触发两种中断方式；输入数据采样不受方向寄存器影响（输入模式可读实际电平）。

| 偏移 | 寄存器 | 说明 |
|---|---|---|
| 0x00 | MODE | 输出模式：0=推挽，1=开漏 |
| 0x04 | DIRECTION | 方向：0=输入，1=输出 |
| 0x08 | OUTPUT | 输出数据寄存器 |
| 0x0C | INPUT | 输入数据寄存器（只读） |
| 0x10 | TR_TYPE | 触发类型：0=电平，1=边沿（逐位） |
| 0x14 | TR_LVL0 | 触发条件 0：电平 0 / 下降沿 |
| 0x18 | TR_LVL1 | 触发条件 1：电平 1 / 上升沿 |
| 0x1C | TR_STAT | 触发状态（写 1 清零） |
| 0x20 | IRQ_EN | 中断使能 |
| 0x24 | BOP_SET | 原子置位（只写，写 1 置位对应输出位） |
| 0x28 | BOP_CLR | 原子复位（只写，写 1 清零对应输出位） |

对应 demo：`blink`（GPIO 输出 LED 闪烁）、`gpio_input`（按键轮询，STM32 风格消抖）。

## UART（apb_uart.sv + uart_rx/tx + uart_download）

兼容 16550 寄存器布局，发送/接收各带 16 字节 FIFO；波特率由 NCO 发生器产生，
`FCW = round(baud × 16 × 2^32 / Fclk)`，`Fclk` 为运行时实测主频
（`soc_init()` 测量，见 `SDK/bsp/soc/soc.h`）。

| 偏移 | DLAB=0 | DLAB=1 |
|---|---|---|
| 0x00 | RBR（接收缓冲）/ THR（发送保持） | DLL（除数低 8 位） |
| 0x04 | IER（中断使能） | DLM（除数高 8 位） |
| 0x08 | IIR（中断标识）/ FCR（FIFO 控制） | — |
| 0x0C | LCR（线控制，bit7=DLAB） | — |
| 0x10 | MCR（调制解调器控制） | — |
| 0x14 | LSR（线状态，只读；bit5=THRE、bit6=TEMT） | — |
| 0x18 | MSR（调制解调器状态，只读） | — |
| 0x1C | DBG_EN（下载使能，只写） | — |
| 0x20 | DBG_STATE / DBG_DONE（bit0=下载完成） | — |
| 0x24 | FCW（NCO 频率控制字） | — |

ITCM/DTCM 下载：帧头 `0xBBAABBAA`，随后 ITCM 指令个数与指令数据（每条 32 位
小端 4 字节），再 DTCM 数据个数与数据；下载完成自动切换用户模式。
协议细节见 [sdk.md](sdk.md)「uartbin 下载协议」。

对应 demo：`uart_echo`（UART 全双工回显）、`hello`（newlib 打印）。

## Timer（apb_timer.sv + basic_timer + timer_ic_oc）

包含 1 个 16 位基本定时器（预分频/自动重载/递增递减）与 4 个输入捕获/输出比较
通道。输出比较（PWM）模式：计数器与 CCR 匹配时产生可配置输出；输入捕获模式：
检测外部引脚上升/下降/双沿并将计数器值锁存至 CCR。

| 偏移 | 寄存器 | 说明 |
|---|---|---|
| 0x00 | TIMx_PSC | 预分频系数 |
| 0x04 | TIMx_CNT | 计数器当前值 |
| 0x08 | TIMx_ARR | 自动重载值 |
| 0x0C | TIMx_CR | 控制：bit0=EN 使能、bit1=CLR 清零、bit2=DIR 方向 |
| 0x10 | TIMx_IER | 中断使能（溢出/捕获/比较） |
| 0x14 | TIMx_SR | 状态（bit0=溢出、bit1=触发，写 1 清零） |
| 0x18 | TIMx_CCMR | 通道模式配置 |
| 0x1C | TIMx_CCER | 通道使能 |
| 0x20~0x2C | TIMx_CCR1~4 | 各通道捕获/比较值 |

对应 demo：`breathing`（Timer PWM 呼吸灯）、`apb_timer_irq`（定时器中断翻转 LED）。

## CLINT（CLINT.sv）

核本地中断控制器，管理软件中断（msip）与定时器中断（mtime ≥ mtimecmp）。
mtime 由独立 1MHz 定时器时钟驱动（`timer_clk_i`），`time`/`timeh` CSR（0xC01/0xC81）
为只读影子；软件中断由向 msip 写 1 产生、写 0 清除。

| 地址 | 寄存器 | 说明 |
|---|---|---|
| +0x0000 | msip | 软件中断挂起（bit0） |
| +0x4000 | mtimecmp[31:0] | 定时器比较值低 32 位 |
| +0x4004 | mtimecmp[63:32] | 定时器比较值高 32 位 |
| +0xBFF8 | mtime[31:0] | 自增计数器低 32 位（只读） |
| +0xBFFC | mtime[63:32] | 自增计数器高 32 位（只读） |

对应 demo：`blink`（用 mtime 实现延时）、`cpuinfo`（CSR dump）。

## PLIC（plic/PLIC.sv）

最多 16 个中断源、7 级优先级（0=禁用，1~7 有效），单目标输出。结构：中断网关
（电平/边沿检测 + Pending 维护，Claim/Complete 握手防重复）→ 优先级仲裁 →
目标（阈值过滤 + Claim/Complete）。

| 地址偏移 | 寄存器 | 说明 |
|---|---|---|
| 0x0000~0x0FFC | Priority | 每源 4 字节优先级配置 |
| 0x1000~0x107C | Pending | 中断等待状态（只读） |
| 0x2000+0x00 | Enable | 中断使能位 |
| 0x2000+0x80 | Threshold | 优先级阈值（低于阈值被屏蔽） |
| 0x2000+0x84 | Claim/Complete | 读=获取待处理中断编号，写=完成处理 |

对应 demo：`plic_irq`（KEY0 按键中断）、`comprehensive_test`（综合中断测试）。

## 中断优先级

处理器核接收三类中断，优先级：**外部中断（PLIC）> 软件中断（CLINT msip）>
定时器中断（CLINT mtime）**；由 CSR `mie` 使能位与 `mip` 挂起位共同控制。

## 上电流程

1. BootROM（MROM）执行：使能 mcycle → 10ms 测频 → 存储实测频率到 DTCM 0x2FFF0 →
   读 GPIO[0] 决定模式 → 下载模式置 DBG_EN=1 等待 uartbin，否则直接跳 ITCM。
2. 应用 `_init()`：`soc_init()` 复测主频并更新 `g_cpu_freq_hz` → `uart_init(115200)`
   （按实测频率计算 FCW）→ 设置 mtvec → `main()`。
