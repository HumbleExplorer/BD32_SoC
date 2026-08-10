# FPGA 原型验证与在线控制工具

> 本页内容自 README 迁移整理，覆盖 FPGA 上板验证、硬件连接、烧录与 UART 自动化工具。

## FPGA 原型验证

Vivado 工程位于 `BD32_SoC/`，目标平台为 Xilinx FPGA。

- 板级顶层：`bd32_board_top`（含 clk_wiz、BUFG、CDC 同步）
- 约束文件：`BD32_SoC.srcs/constrs_1/new/BD32_SoC.xdc`
- IP：clk_wiz_0（时钟生成）、imem/dmem/mrom（Block Memory Generator）
- 支持 ILA 在线调试（`mark_debug` 属性标注关键信号）
- 支持 UART 下载模式（MROM 自动计算波特率并配置 UART）


## FPGA 在线控制工具（SDK/tools）

通过 USB 连接 Sipeed RV-Debugger（FTDI FT2232H）和板载 CH340 USB-UART，可以在 PC 端用 Python 脚本完成复位、程序烧录、串口收发等操作，无需手动按复位键或打开串口助手。

## 硬件连接与驱动

| 设备 | 用途 | 驱动 |
|------|------|------|
| Sipeed RV-Debugger (FT2232H) Ch.A | JTAG 调试（OpenOCD） | WinUSB（Zadig 替换） |
| Sipeed RV-Debugger (FT2232H) Ch.A | FPGA 复位（ADBUS5 bit-bang） | D2XX (ftd2xx) |
| 板载 CH340 USB-UART | 程序下载 + 输出接收 | Windows VCP（COM 口） |

Python 依赖：

```bash
pip install ftd2xx pyserial
```

注意：fpga_reset.py 默认通过 OpenOCD 驱动 FTDI ADBUS5 实现复位（参考 E203 SDK openocd_evalsoc.cfg，配置见 `bd32_reset.cfg`），**WinUSB 模式即可，无需切换驱动**。仅 `--assert/--release`（跨会话保持复位）才需要 ftd2xx（FTDI VCP 驱动，与 OpenOCD/WinUSB 互斥）。日常流程（复位 → UART 下载 → 调试）保持 WinUSB 即可。

所有串口工具默认自动检测 CH340（通过 USB VID:PID = 1A86:7523 匹配），无需手动指定 COM 口号。该编号标识的是 CH340 芯片型号而非特定板卡，因此更换任何使用 CH340 的开发板均可自动识别。若同时连接多块 CH340 板，需用 `--port COMx` 手动指定。

## FPGA 复位（fpga_reset.py）

通过 FTDI bit-bang 模式驱动 ADBUS5（高电平有效）实现软件复位：

```bash
cd SDK

# 复位一次（拉高 0.5 秒后自动释放）
python tools/fpga_reset.py

# 保持复位 3 秒后释放
python tools/fpga_reset.py --hold 3

# 仅拉高复位（不释放，用于调试）
python tools/fpga_reset.py --assert

# 仅释放复位
python tools/fpga_reset.py --release
```

原理：FT2232H Channel A 设为 bit-bang 模式（0x01），ADBUS5 作为输出。写 `0x20` 拉高触发复位，写 `0x00` 释放。FPGA 端 `bd32_board_top` 中 `dbg_rst` 信号参与复位逻辑：`rst_async_n = sys_rst_n && (~dbg_rst) && clk_wiz_locked`。

## 自动化程序烧录与测试（auto_coremark.py）

一键完成：复位 → UART 下载程序 → 等待运行完成 → 解析输出结果。

```bash
cd SDK

# 跑全部 9 个 CoreMark 配置（GCC Os/O1/O2/O3 + LLVM Os/Oz/O1/O2/O3）
python tools/auto_coremark.py

# 只跑单个配置（按文件名匹配）
python tools/auto_coremark.py --config coremark_o2

# 指定串口和波特率
python tools/auto_coremark.py --port COM8 --baud 115200

# 指定 uartbin 文件目录
python tools/auto_coremark.py --data-dir <uartbin 文件目录>
```

输出示例：

```
============================================================
  Config: GCC O2
  File:   <工作目录>\test_data\soc\c\coremark_o2.uartbin
============================================================
  [1/4] Resetting FPGA...
  [2/4] Downloading program...
    Sending 22824 bytes (90 chunks)...
    Send complete.
  [3/4] Running CoreMark...
  [4/4] Parsing results...
    CoreMark/MHz:   2.7906
    Iterations/Sec: 223.2513
    Total ticks:    179170236
    Branch hit:     0.9756
```

运行前确保：COM 口未被其他程序（串口助手等）占用；Sipeed RV-Debugger 已插入 USB。

## 手动 UART 发送程序（uart_send.py）

将 .uartbin 文件通过串口下载到 FPGA（发送前需先复位，或加 `--reset` 自动复位）：

```bash
cd SDK

# 先复位再下载（推荐）
python tools/uart_send.py test_data/soc/c/coremark_o2.uartbin --reset

# 仅下载（需提前手动复位）
python tools/uart_send.py test_data/soc/c/coremark_o2.uartbin

# 指定串口
python tools/uart_send.py coremark_o2.uartbin --port COM8 --baud 115200
```

uartbin 文件格式（由 build.py 自动生成，完整协议见下文「下载协议」节）：

```
START_FRAME (4B: 0xBBAABBAA, 小端) → ITCM_COUNT (4B LE) → ITCM_DATA → DTCM_COUNT (4B LE) → DTCM_DATA
```

## 手动 UART 发送命令/文本（uart_cmd.py）

向串口发送任意文本或原始字节：

```bash
cd SDK

# 发送文本（自动加换行）
python tools/uart_cmd.py "hello"

# 不加换行
python tools/uart_cmd.py "hello" --no-newline

# 发送原始十六进制字节
python tools/uart_cmd.py --hex "AA BB CC 01"

# 发送文件内容
python tools/uart_cmd.py --file cmd.txt
```

## 手动 UART 接收输出（uart_recv.py）

监听串口并实时打印到终端：

```bash
cd SDK

# 监听 30 秒（默认）
python tools/uart_recv.py

# 监听 60 秒
python tools/uart_recv.py --timeout 60

# 收到包含指定字符串后自动停止
python tools/uart_recv.py --until "CoreMark/MHz"
```

按 Ctrl+C 可随时中断。

## 将接收数据写入文件（uart_log.py）

监听串口并将输出保存到日志文件：

```bash
cd SDK

# 监听 30 秒，写入 output.log
python tools/uart_log.py output.log

# 监听 60 秒
python tools/uart_log.py result.txt --timeout 60

# 收到 "DONE" 后停止
python tools/uart_log.py log.txt --until "DONE"

# 追加模式（不覆盖已有内容）
python tools/uart_log.py log.txt --append

# 静默模式（只写文件，不打印到终端）
python tools/uart_log.py log.txt --quiet
```

## 典型组合用法

```bash
cd SDK

# 复位 → 下载 → 接收结果到文件（三条命令）
python tools/fpga_reset.py
python tools/uart_send.py test_data/soc/c/coremark_o2.uartbin
python tools/uart_log.py result.log --until "CoreMark/MHz" --timeout 30

# 或者一步到位（uart_send 自带 --reset）
python tools/uart_send.py test_data/soc/c/coremark_o2.uartbin --reset
python tools/uart_log.py result.log --until "CoreMark/MHz"

# 全自动 9 配置跑分（含复位+下载+解析+汇总）
python tools/auto_coremark.py 2>&1 | tee tools/coremark_results.log
```

