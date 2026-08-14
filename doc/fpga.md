# FPGA 原型验证与在线控制工具

> 本页内容自 README 迁移整理，覆盖 FPGA 上板验证、硬件连接、烧录与 UART 自动化工具。

## FPGA 原型验证

Vivado 工程位于 `BD32_SoC/`，目标器件为 **Xilinx ZYNQ-7020（xc7z020clg400-2）**。

- 板级顶层：`bd32_board_top`（含 clk_wiz、BUFG、CDC 同步）
- 约束文件：`BD32_SoC.srcs/constrs_1/new/BD32_SoC.xdc`
- IP：clk_wiz_0（时钟生成）、imem/dmem/mrom（Block Memory Generator）
- 支持 UART 下载模式（MROM 自动计算波特率并配置 UART）

> ⚠️ 引脚约束（`BD32_SoC.xdc`）按当前板卡（ZYNQ7020CLG400-2）的封装与引脚编写——时钟、复位、UART、JTAG/复位调试引脚都是具体 `PACKAGE_PIN`。**更换板卡时必须自行修改 XDC 中的引脚与电平标准**，否则综合/实现可能报错或上板不工作。


## FPGA 在线控制工具（SDK/tools）

通过 USB 连接 Sipeed RV-Debugger（FTDI FT2232H）和板载 CH340 USB-UART，可以在 PC 端用 Python 脚本完成复位、程序烧录、串口收发等操作，无需手动按复位键或打开串口助手。

## 硬件连接与驱动

| 设备 | 用途 | 驱动 |
|------|------|------|
| Sipeed RV-Debugger (FT2232H) Ch.A | JTAG 调试（OpenOCD） | WinUSB（Zadig 一次性绑定） |
| Sipeed RV-Debugger (FT2232H) Ch.A | FPGA 复位（ADBUS5 bit-bang，OpenOCD） | WinUSB（ftd2xx 仅回退） |
| 板载 CH340 USB-UART | 程序下载 + 输出接收 | Windows VCP（COM 口） |

Python 依赖：

```bash
pip install pyserial
# ftd2xx 可选：仅当 OpenOCD 复位不可用时作为回退（一般不需要）
pip install ftd2xx
```

注意：fpga_reset.py 通过 OpenOCD 驱动 FTDI ADBUS5 实现复位（参考 E203 SDK openocd_evalsoc.cfg，配置见 `bd32_reset.cfg`），`--assert` / `--release` / `--hold` 均走 OpenOCD，**WinUSB 模式即可，无需切换驱动**。仅在 OpenOCD 不可用时可加 `--method ftd2xx` 回退（需 FTDI VCP 驱动，与 WinUSB 互斥）。日常流程（复位 → UART 下载 → 调试）保持 WinUSB 即可。

所有串口工具默认自动检测 CH340（通过 USB VID:PID = 1A86:7523 匹配），无需手动指定 COM 口号。该编号标识的是 CH340 芯片型号而非特定板卡，因此更换任何使用 CH340 的开发板均可自动识别。若同时连接多块 CH340 板，需用 `--port COMx` 手动指定。

## 使用 Zadig 绑定 WinUSB（一次性）

OpenOCD（JTAG 与复位）通过 libusb 访问 FT2232H，Windows 上需把 Channel A 绑定为 WinUSB 驱动。用 [Zadig](https://zadig.akeo.ie/) 操作一次即可，之后保持 WinUSB 无需再切换：

1. 下载并运行 Zadig（免安装绿色工具）。
2. 菜单 **Options → List All Devices**，在下拉框选择 **Dual RS232-HS (Interface 0)**（VID:PID = `0403:6010`）。FT2232H 有两个接口，务必选 **Interface 0 / Channel A**。
3. 右侧目标驱动选择 **WinUSB**（若已显示 WinUSB，说明已绑定，直接关闭即可）。
4. 点击 **Replace Driver**，完成后在设备管理器确认 Channel A 显示为 WinUSB 设备。
5. 重新插拔调试器（或重新枚举），确认 OpenOCD 可正常连接。

注意事项：
- 只改 FT2232H Channel A（`0403:6010` 接口 0）；**不要**给 CH340（`1A86:7523`，串口）换驱动，它保持 VCP 即可。
- Channel B（接口 1）本工程未使用，保持默认驱动。
- 与 Vivado Hardware Manager 冲突时，先关闭 `hw_server` 再使用 OpenOCD。
- 换电脑或驱动被改回 VCP 后，重复本流程即可。

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

原理：FT2232H 的 Channel A 提供 8 根通用 GPIO 引脚 ADBUS0~7，可设为 **bit-bang（位带）模式**——由软件逐位直接控制每个引脚的电平（写 0/1 拉高/拉低），而不是走片内 UART/MPSSE 等硬件协议引擎。复位用的是 **ADBUS5**（第 6 根引脚，bit5 = 0x20），在 Sipeed RV-Debugger 上接到了 FPGA 的复位脚 `dbg_rst`（高有效）。`fpga_reset.py` 中 `RST_BIT = 0x20` 即对应 ADBUS5：写 `0x20` 拉高触发复位，写 `0x00` 释放。FPGA 端 `bd32_board_top` 中 `dbg_rst` 参与复位逻辑：`rst_async_n = sys_rst_n && (~dbg_rst) && clk_wiz_locked`。

## 自动化程序烧录与测试（auto_coremark.py）

一键完成：复位 → UART 下载程序 → 等待运行完成 → 解析输出结果。

```bash
cd SDK

# 跑全部 9 个 CoreMark 配置（GCC Os/O1/O2/O3 + LLVM Oz/Os/O1/O2/O3）
python tools/auto_coremark.py

# 只跑单个配置：编译器 + 优化等级（如 GCC O2）
python tools/auto_coremark.py --compiler gcc --opt o2

# 只跑某个编译器的全部优化等级（如 LLVM/Clang）
python tools/auto_coremark.py --compiler clang

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

运行前确保：COM 口未被其他程序（串口助手等）占用；Sipeed RV-Debugger （用于复位）已插入 USB。

## 手动 UART 发送程序（uart_send.py）

将 .uartbin 文件通过串口下载到 FPGA（发送前需先复位，或加 `--reset` 自动复位）：

```bash
cd SDK

# 先复位再下载（推荐）；uartbin 默认在 test_data/soc/c 下查找，也可传完整路径
python tools/uart_send.py coremark_o2.uartbin --reset

# 仅下载（需提前手动复位）
python tools/uart_send.py coremark_o2.uartbin

# 指定串口
python tools/uart_send.py coremark_o2.uartbin --port COM8 --baud 115200

# 下载后监听：输出空闲 3 秒即停（--idle-timeout，默认 3s）；日志自动写入 logs/uart_send_<程序>_<时间戳>.log，可用 --log 指定
python tools/uart_send.py uart_echo.uartbin --reset --idle-timeout 3

# CoreMark 这类“中途静默、结尾有标志”的程序，可用 --until 精确停在标记末尾
python tools/uart_send.py coremark_o2.uartbin --reset --until "Correct operation validated."
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

# 发送后监听响应：空闲 3 秒即停（--idle-timeout），或 --until 精确停在标记末尾；日志自动写入 logs/uart_cmd_<时间戳>.log
python tools/uart_cmd.py "hi" --idle-timeout 3
python tools/uart_cmd.py "hi" --until "Done!"
```

## 手动 UART 接收输出（uart_recv.py）

监听串口并实时打印到终端，可用 `--output` 同时写入文件：

```bash
cd SDK

# 监听 30 秒（默认）
python tools/uart_recv.py

# 监听 60 秒
python tools/uart_recv.py --timeout 60

# 收到包含指定字符串后自动停止
python tools/uart_recv.py --until "CoreMark/MHz"

# 同时写入文件（覆盖；追加用 --append，静默用 --quiet）
python tools/uart_recv.py --output result.log
python tools/uart_recv.py --output log.txt --append --quiet
```

按 Ctrl+C 可随时中断。

## 典型组合用法

```bash
cd SDK

# 复位 → 下载 → 同一进程内继续监听，输出空闲 3 秒即停并写日志（推荐）
python tools/uart_send.py coremark_o2.uartbin --reset --idle-timeout 3

# CoreMark 计算间隙较长，也可用 --until 精确停在结束标记
python tools/uart_send.py coremark_o2.uartbin --reset --until "Correct operation validated."

# 全自动 9 配置跑分（含复位+下载+解析+汇总）
# Windows cmd：重定向到文件；PowerShell：Tee-Object 同时回显
python tools/auto_coremark.py > tools\coremark_results.log 2>&1
python tools/auto_coremark.py | Tee-Object tools\coremark_results.log

# uart_echo 完整流程：下载并确认启动横幅 → 发送文本验证回显与退出
python tools/uart_send.py uart_echo.uartbin --reset --idle-timeout 3
python tools/uart_cmd.py "hi" --idle-timeout 3
```

> 注意：Windows 串口为独占访问，无法用两个进程同时收发。先启动 `uart_recv.py --output` 再发送会打不开端口；先发送完再启动监听则会丢掉程序开头的输出（`uart_recv` 打开时还会清空接收缓冲）。需要抓取运行输出的场景，请用上面的 `--idle-timeout`（输出空闲即停）或 `--until`（精确标记），或直接用 `auto_coremark.py`。`uart_recv.py --output` 适合程序已在运行、只想记录当前串口输出时使用。
