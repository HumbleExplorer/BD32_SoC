# 外设编程指南

所有外设挂在 APB 总线（经 AXI-APB 桥），寄存器按 32-bit 字访问。

## 地址映射

| 外设 | 基地址 | PSEL |
|---|---|---|
| CLINT | 0xF200_0000 | 0 |
| PLIC | 0xFC00_0000 | 1 |
| GPIO | 0xE000_0000 | 2 |
| UART | 0xE001_0000 | 3 |
| Timer | 0xE002_0000 | 4 |
| SPI / I2C | 0xE003_0000 / 0xE004_0000 | 5/6（预留） |

## UART

NCO 波特率发生器：`FCW = round(baud × 16 × 2^32 / Fclk)`，`Fclk` 为运行时实测主频
（`soc_init()` 测量，见 `SDK/bsp/soc/soc.h`）。

| 偏移 | 寄存器 | 说明 |
|---|---|---|
| 0x00 | THR/RBR/DLL | 发送保持/接收缓冲（DLAB=1 时 DLL） |
| 0x04 | IER/DLM | 中断使能（DLAB=1 时 DLM） |
| 0x08 | IIR/FCR | 中断标识 / FIFO 控制 |
| 0x0C | LCR | 线控制（bit7=DLAB） |
| 0x10 | MCR | 调制解调器控制 |
| 0x14 | LSR | 线状态（bit5=THRE、bit6=TEMT） |
| 0x18 | MSR | 调制解调器状态 |
| 0x1C | DBG_EN | 下载模式使能 |
| 0x20 | DBG_DONE | bit0=下载完成 |
| 0x24 | FCW | NCO 频率控制字 |

uartbin 下载协议见 README「uartbin 下载协议」。

## CLINT

| 偏移 | 寄存器 |
|---|---|
| 0x0000 | msip（软件中断挂起） |
| 0x4000 | mtimecmp（低/高 32 位） |
| 0xBFF8 | mtime（低/高 32 位，1MHz 独立时钟域） |

mtime 由独立 1MHz 定时器时钟驱动；`time`/`timeh` CSR（0xC01/0xC81）为只读影子。

## PLIC

标准 PLIC 结构（优先级 / 使能 / 挂起 / 阈值 / Claim-Complete），位于 0xFC00_0000。

## GPIO

| 偏移 | 寄存器 |
|---|---|
| 0x04 | DIR（方向） |
| 0x08 | OUTPUT |
| 0x0C | INPUT |

## Timer / PWM

APB Timer 支持基本定时、输出比较（PWM）、输入捕获；中断经 PLIC 路由。

## 上电流程

1. BootROM（MROM）执行：使能 mcycle → 10ms 测频 → 存储实测频率到 DTCM 0x2FFF0 →
   读 GPIO[0] 决定模式 → 下载模式置 DBG_EN=1 等待 uartbin，否则直接跳 ITCM。
2. 应用 `_init()`：`soc_init()` 复测主频并更新 `g_cpu_freq_hz` → `uart_init(115200)`
   （按实测频率计算 FCW）→ 设置 mtvec → `main()`。
