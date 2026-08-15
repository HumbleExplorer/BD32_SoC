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
- 长指令（MUL/DIV/REM）在 EX 阶段分发到 OITF，由独立功能单元执行，完成后经 Port2 乱序写回。
- OITF 维护 RAW/WAW 冒险检测，必要时 stall 整条流水线。
- 寄存器堆双写端口：Port1（正常 WB）与 Port2（OITF 退休），同地址冲突时 Port2 优先；
  旁路读取优先级 Port2 > Port1 > 寄存器阵列。

## 运算单元

- 乘法：4 级流水基 4 Booth 乘法器（S0 输入+部分积 → S1 压缩 → S2 CLA+修正 → S3 输出；每拍可接受新输入）。
- 除法：32 周期迭代恢复余数除法器。

## 分支预测

分支预测单元（BPU）采用 **Gshare（方向）+ BTB（目标地址）+ RAS（调用/返回）** 方案：

- **方向预测（Gshare）**：PHT 存 2 位饱和计数器，索引 = PC 哈希值 ⊕ 全局历史寄存器（GHR）；GHR 记录最近分支的实际跳转方向，利用分支间相关性提高准确率。
- **目标地址（BTB）**：直接映射，每项含 Valid / Type / Tag / Target；以 PC 低位索引，查得的 Target 与 PC 高位拼接（压缩 Tag/Target 位宽、省面积，略微增加别名）。
- **返回地址（RAS）**：JAL（rd=x1/x5）视为调用入栈，RET（JALR 且 rs1 为 link 类）出栈；BTB 指令类型为 RET 时取 RAS 栈顶作为预测地址。JALR 的入栈/出栈按 RISC-V 规范表（rd/rs1 是否 link、rs1==rd）执行。
- **两阶段流程**：IF 推测（按 PC 查 BTB/PHT，RET 用 RAS 栈顶）；EX 更新（PHT 计数器、GHR 移位写入实际方向、BTB 新增/修改、RAS 压栈/出栈）。
- PC 更新优先级：中断/异常 > 分支预测失败（EX）> 预测跳转（IF）> 停顿 > PC+4。
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
| `MULT_PIPELINE` | 4 级流水乘法器 |
| `XILINX` | FPGA 综合模式（BRAM IP） |
| `BD32_DEBUG_EN` | 使能调试子系统 |
| `WB_TRACE` | 写回追踪输出 |
