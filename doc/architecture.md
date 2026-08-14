# BD32 微架构

## 概览

BD32 是 32 位 RV32IM 处理器，经典 5 级流水线（IF → ID → EX → MEM → WB），
配备深度 4 的 OITF（乱序退休 FIFO），让多周期乘除指令可与短指令并行执行、乱序写回。

```
┌────┐   ┌────┐   ┌────┐   ┌────┐   ┌────┐
│ IF │──▶│ ID │──▶│ EX │──▶│MEM │──▶│ WB │──▶ Port1 写回
└────┘   └────┘   └────┘   └────┘   └────┘
                      │                            ▲
                      ▼                            │
                 ┌──────────┐    retire            │
                 │   OITF   │────────────────────────▶ Port2 写回
                 │ (depth=4)│
                 └──────────┘
                   ▲      ▲
                   │      │
              ┌────┴┐  ┌──┴───┐
              │ MUL │  │ DIV  │
              │3-cyc│  │32-cyc│
              └─────┘  └──────┘
```

## 流水线

- 短指令（ALU / Load / Store / Branch）走正常 5 级流水，WB 阶段经 Port1 写回。
- 长指令（MUL/DIV/REM）在 EX 阶段分发到 OITF，由独立功能单元执行，完成后经 Port2 乱序退休。
- OITF 维护 RAW/WAW 冒险检测，必要时 stall 整条流水线。
- 寄存器堆双写端口：Port1（正常 WB）与 Port2（OITF 退休），同地址冲突时 Port2 优先；
  旁路读取优先级 Port2 > Port1 > 寄存器阵列。

## 运算单元

- 乘法：3 级流水 Booth-4 乘法器（3 拍出结果）。
- 除法：32 周期迭代恢复除法器（`divider.sv`，含溢出标记）。

## 分支预测

- 动态分支预测器 + 返回地址栈（RAS）。
- 调试单步模式下自动门控预测跳转，保证 PC 严格 +4 递增。

## 存储器与总线

| 区域 | 地址 | 说明 |
|------|------|------|
| BootROM | 0x0000_0000 | 4KB，上电执行（MROM 测频 → 初始化 UART → 跳 ITCM） |
| ITCM | 0x0001_0000 | 64KB，代码段（同步读） |
| DTCM | 0x0002_0000 | 64KB，数据段 |
| GPIO | 0xE000_0000 | APB |
| UART | 0xE001_0000 | APB |
| Timer | 0xE002_0000 | APB |
| SPI / I2C | 0xE003_0000 / 0xE004_0000 | 预留 |
| CLINT | 0xF200_0000 | mtime/mtimecmp/msip |
| PLIC | 0xFC00_0000 | 中断控制器 |
| Flash / DDR | 0x9000_0000 / 0xB000_0000 | AXI 从机未实现，访问返回错误 |

- Debug Module：不占用系统地址空间（非内存映射外设），经 JTAG DMI 访问核心寄存器/CSR；SBA 按地址在核内分发——BootROM/ITCM/DTCM 直连，总线区（外设等）借用 CPU 侧总线主机口发起事务（AXI 互联层仅一个主机）。
- 总线：AXI-Lite 主接口 + AXI Interconnect（APB 桥 + 错误从机）+ APB 外设互联。
- 时钟：FPGA 板级 MMCM 输出 CPU 时钟（75MHz）；CLINT 由独立 1MHz 定时器时钟驱动。

## 调试挂钩

核通过专用端口与 Debug Module 交互（halt/resume/step、GPR/CSR 直连、SBA 总线访问、
Trigger 断点/观察点、ebreak 进调试），详见 [调试模块](debug_module.md)。

## 关键配置宏（`rtl/SoC_Config.sv`）

| 宏 | 功能 |
|---|---|
| `DIRECT_LOAD` | 从 .mem 直接加载程序（跳过 UART 下载） |
| `CORE_TEST` | 核级测试模式 |
| `CUSTOM_ASM` | 使用 custom_asm 测试路径 |
| `MULT_PIPELINE` | 3 级流水乘法器 |
| `XILINX` | FPGA 综合模式（BRAM IP） |
| `BD32_DEBUG_EN` | 使能调试子系统 |
| `WB_TRACE` | 写回追踪输出 |
