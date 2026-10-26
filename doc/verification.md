# 验证手册

> 完整验证流程：构建 → 仿真 → 上板 → 基准/差分测试 → 回归建议。
> 环境依赖与工具安装见 README「快速开始-环境准备」；构建工具与协议见 [SDK 构建工具与协议](sdk.md)；RT-Thread 应用开发（版本、中断模式、编程模板）见 sdk.md「RT-Thread 应用开发」。
> 本手册说明验证脚本的运行方式、判据及当前覆盖范围；项目功能概况见 README。

## 构建固件与测试

### 自定义汇编测试

```bash
cd test_data/custom_asm
python build_asm.py <test_name>    # 单个测试
python build_asm.py all            # 全部 52 个测试
```

编译参数：`-march=rv32im -mabi=ilp32 -O0 -mno-relax -nostdlib -static`；产物 `.elf` / `.dump` / `.dat`（readmemh 字流）。

### C 程序 / CoreMark

```bash
cd SDK

# 裸机 demo
python tools/build.py demos/nolibc/breathing
python tools/build.py demos/nolibc/breathing --newlib    # 链接 newlib-nano
python tools/build.py demos/nolibc/breathing --clang     # 用 Clang 前端

# CoreMark（产物含优化等级后缀：coremark_o2_*.mem / coremark_o3_*.mem）
python tools/build.py demos/newlib/coremark --newlib --opt O2
python tools/build.py demos/newlib/coremark --newlib --opt O3

# 极致体积：Clang + LLD（LTO + ICF），当前最小配置（详见 sdk.md「LLVM/Clang 集成与代码体积优化」）
python tools/build.py demos/newlib/coremark --picolibc --clang --lld
```

产物：`.elf`、`.dump`、`*_itcm.mem`、`*_dtcm.mem`、`.uartbin`（CoreMark 文件名含 `_o2`/`_o3` 后缀），默认 Os 构建的 uartbin 带 `_os` 后缀（如 `hello_os.uartbin`）。

> C 库默认使用 **newlib-nano**（`-specs=nano.specs` 精简版，`printf`/`malloc` 可用），可通过--picolibc用picolibc；`--newlib` 与 `--rtthread` 均链接 newlib-nano。

### RT-Thread 程序

```bash
cd SDK
python tools/build.py demos/rtthread --rtthread                     # lts-v3.1.x（默认）
python tools/build.py demos/rtthread --rtthread --irq-mode unified  # 统一入口中断模式
python tools/build.py demos/rtthread --rtthread --picolibc          # lts-v3.1.x + picolibc
python tools/build.py demos/rtthread51 --rtthread --rtthread-version 51   # v5.1.0
python tools/build.py demos/rtthread51 --rtthread --rtthread-version 51 --picolibc  # v5.1.0 + picolibc
```

`--rtthread` 模式自动启用 newlib-nano 链接。版本/目录对应、中断模式选择与编写 RT-Thread 程序的说明见 sdk.md「RT-Thread 应用开发」。

## 仿真验证（ModelSim）

### 验证矩阵

| 套件          | 顶层                                                     | 运行                                                                                         | 判定                                                                       |
| ----------- | ------------------------------------------------------ | ------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------ |
| custom_asm  | tb_core_top                                            | `script/run_all_custom_asm.py`                                                             | 52/52 全过（自定义压力测试）                                                        |
| riscv-tests | tb_core_top                                            | `script/run_all_riscv_tests.py`                                                            | 51/51 全过（含 fence_i / ma_data / rvc）                                      |
| Debug 模块    | tb_debug                                               | `script/debug_test/run_msim_debug.bat`                                                     | 94 PASS / 0 FAIL                                                         |
| 外设          | tb_apb_uart / tb_apb_gpio / tb_apb_plic / tb_apb_timer | `script/run_periph_regression.bat`                                                         | 全部通过（UART 为 24 用例全寄存器套件，含 IIR 五子源/LSR 四位错误/FCR 触发级与清 FIFO/5-7 数据位/两位停止位） |
| AXI 互联链     | tb_axi_interconnect                                    | `script/axi_test/run.do`                                                                   | 7 用例（路由回环 / 错误响应 / 超时有界）全过                                               |
| UART 下载长流   | tb_uart_dl_file / tb_uart_dl_mini                      | `script/uart_test/run_file.do`（8x）/ `run_mini.do`                                          | RX→FIFO→下载 FSM 全字比对零不一致（已并入外设回归）                                          |
| SoC         | tb_soc_top                                             | `script/run_soc_test.bat`                                                                  | 默认程序启动输出无异常                                                              |
| RT-Thread   | tb_soc_top                                             | `script/soc_test/rtthread_sim*.do`（含 `rtthread_sim315_pico.do` / `rtthread_sim51_pico.do`） | lts-v3.1.x / v5.1.0 × newlib / picolibc，多任务并发运行                          |

### 运行方式

各套件均可一键运行，也可手动执行。涉及 ModelSim 的脚本统一用 `-batch` headless 模式，输出重定向到仓库根 `logs/`，license 通过环境变量 `MGLS_LICENSE_FILE` 指定。

- **全量一键回归**：`script/run_all_verification.bat`（依次执行下面 1~6 全部套件，约 1~1.5 小时，进度/退出码实时写入 `logs/verify_all_mark.txt`）。

- **核级（tb_core_top）**：
  ```bash
  cd script
  python run_one.py <test_name>              # 单个 custom_asm 测试
  python run_all_custom_asm.py               # custom_asm 全回归（52 项）
  python run_hpm_audit.py                    # HPM 审计：参考模型逐项核对（HPM AUDIT: ALL PASS）
  python run_all_riscv_tests.py              # riscv-tests 回归（51 项）
  ```
  **判定约定**：x26=1 完成、x27=1 通过、x3(gp) 记录失败子测试编号。

  SVA 回归判据见「SVA 断言体系」章节。
  
- **SoC 级（tb_soc_top）**：一键 `run_soc_test.bat`（输出 `logs/soc_test_out.txt`），或手动：
  
  ```bash
  cd script/soc_test
  vlog -f filelist.f +define+DIRECT_LOAD     # 编译
  vsim -c -voptargs=+acc tb_soc_top -do "run 15ms; quit -f"
  ```
  默认程序启动输出即验证 CPU/UART 通路；UART 输出经 TB 的 `$write("%c", ...)` 打印到控制台；添加 `+define+WB_TRACE` 可启用写回追踪（`wb_trace.log`）。
  
- **RT-Thread**：一键脚本按 内核版本 × C 库 组合：`run_rtthread_sim.bat`（lts-v3.1.x newlib）、`run_rtthread_sim315_pico.bat`（lts-v3.1.x + picolibc）、`run_rtthread_sim51.bat`（v5.1.0 newlib）、`run_rtthread_sim51_pico.bat`（v5.1.0 + picolibc），输出对应 `logs/rtthread_sim*_out.txt`；或手动：
  ```bash
  cd script/soc_test
  vsim -batch -do "do rtthread_sim.do"             # lts-v3.1.x newlib：加载 rtthread_os_*.mem
  vsim -batch -do "do rtthread_sim315_pico.do"     # lts-v3.1.x + picolibc：加载 rtthread_picolibc_os_*.mem
  vsim -batch -do "do rtthread_sim51.do"           # v5.1.0 newlib：加载 rtthread51_os_*.mem
  vsim -batch -do "do rtthread_sim51_pico.do"      # v5.1.0 + picolibc：加载 rtthread51_picolibc_os_*.mem
  ```
  `rtthread_sim*.do` 通过 `+define+ITCM_FILE/DTCM_FILE` 加载 `test_data/soc/c/rtthread*_os_*.mem`（构建产物自动同步，中断模式不影响产物名），输出 RT-Thread 启动横幅及 t1/t2 双线程交替打印即通过。仿真窗口取 80ms：soc_init 频率测量约占 10ms、UART 打印约占 11ms，需覆盖至少两轮线程延时唤醒以确认轮转稳定。

- **Debug**：`script/debug_test/run_msim_debug.bat`（94 项回归，输出 `logs/msim_out.txt`）。

- **外设**：`script/run_periph_regression.bat`（UART / GPIO / PLIC / Timer 四合一，输出 `logs/*_test_out.txt`）。

- **GUI / 交互**：每个 `script/xxx_test/` 目录（含 `core_test`、`soc_test` 与外设测试）可双击 `top_tb.bat` 打开 ModelSim GUI，或命令行执行 `run.do`：
  ```bash
  cd script/uart_test
  <ModelSim 安装目录>\win64\modelsim -do run.do   # 或 modelsim -do run.do（已加入 PATH）
  ```

### script/ 目录脚本索引

`script/` 集中存放仿真验证脚本。

**script/ 根目录（工具脚本）**

| 脚本                          | 用途                                                                                                                                | 用法                                                                                                                                      |
| --------------------------- | --------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------- |
| `run_one.py`                | 运行单个 custom_asm 测试                                                                                                                | `cd script && python run_one.py <test_name>`                                                                                            |
| `run_all_custom_asm.py`     | custom_asm 全回归（tb_core_top）                                                                                                       | `cd script && python run_all_custom_asm.py`                                                                                             |
| `run_all_riscv_tests.py`    | riscv-tests ISA 兼容性回归（tb_core_top）                                                                                                | `cd script && python run_all_riscv_tests.py`                                                                                            |
| `cleanup_temp.py`           | 清理 ModelSim work 库、transcript/*.log/wlft*/vsim.wlf/modelsim.ini、`__pycache__`、logs/；`--remove-builds` 可同时删除 build/、build_* 构建产物目录 | `cd script && python cleanup_temp.py [--apply] [--dry-run] [--keep-logs] [--remove-builds]`（默认先列出并确认；`--apply` 跳过确认直接删；`--dry-run` 只列出） |
| `run_periph_regression.bat` | 外设四合一 headless 回归（UART/GPIO/PLIC/Timer），输出 `logs/*_test_out.txt`                                                                  | 直接运行                                                                                                                                    |
| `run_soc_test.bat`          | SoC headless 仿真（tb_soc_top，默认程序启动），输出 `logs/soc_test_out.txt`                                                                     | 直接运行                                                                                                                                    |

**script/<test>/ 仿真脚本**（每个测试目录含 `run.do` + `top_tb.bat` + `filelist.f` + `wave.do`）：

| 目录 | 测试对象 | 脚本 | 说明 |
|------|----------|------|------|
| `core_test/` | 核级 tb_core_top | `run.do`（GUI）；`core_run_batch.do` / `run_core.do`（batch）；`top_tb.bat`（GUI 启动） | custom_asm / riscv-tests 由根目录 Python 脚本驱动 |
| `debug_test/` | 调试模块 tb_debug | `run.do`（GUI）；`run_msim_debug.bat`（headless 回归，输出 `logs/msim_out.txt`）；`run_batch.do` | Debug Spec 全功能 94 项回归（默认加载 breathing，可用 `BD32_ITCM_FILE` / `BD32_DTCM_FILE` 环境变量指定 .mem） |
| `soc_test/` | SoC 级 tb_soc_top | `top_tb.bat`（GUI 启动）；`run.do`（主仿真） | 各自带波形配置，batch 场景加 `quit -f`；复位/总线超时/诊断等用例脚本见目录内同名 .do |
| `gpio_test/` `plic_test/` `timer_test/` `uart_test/` | 外设独立 tb_apb_* | `run.do`（GUI）；`top_tb.bat` | 独立于 CPU 的外设仿真 |
| `axi_test/` | AXI 互联链 tb_axi_interconnect | `run.do`（batch） | axi_lite_master_bfm 驱动全真实 DUT 链（互联 → 桥+APB 桩 / err_slave×2）：路由回环、随机等待态压力、PSLVERR→SLVERR、err 段 OKAY+0、从机无响应→桥超时、未路由段 BFM 有界超时 |

说明：
- `run.do` 第一行统一用 `file delete -force work` 清理旧库，不依赖 `vdel`/`modelsim.ini`，避免 GUI 锁库时报错。
- 涉及 ModelSim 的批处理脚本输出统一重定向到仓库根 `logs/`；ModelSim license 通过 `MGLS_LICENSE_FILE` 指定。
- 仿真回归脚本统一使用 `-batch` 无界面模式，适合脚本自动化。

## 上板验证

### 硬件连接与驱动

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

注意：fpga_reset.py 通过 OpenOCD 驱动 FTDI ADBUS5 实现复位，`--assert` / `--release` / `--hold` 均走 OpenOCD，**WinUSB 模式即可，无需切换驱动**。仅在 OpenOCD 不可用时可加 `--method ftd2xx` 回退（需 FTDI VCP 驱动，与 WinUSB 互斥）。日常流程（复位 → UART 下载 → 调试）保持 WinUSB 即可。

所有串口工具默认自动检测 CH340（USB VID:PID = 1A86:7523），无需手动指定 COM 口号；同时连接多块 CH340 板时用 `--port COMx` 手动指定。

Vivado 工程位于 `BD32_SoC/`，目标器件 **Xilinx ZYNQ-7020（xc7z020clg400-2）**；板级顶层 `bd32_board_top`，约束文件 `BD32_SoC.srcs/constrs_1/new/BD32_SoC.xdc`。

> ⚠️ 引脚约束（`BD32_SoC.xdc`）按当前板卡封装编写——时钟、复位、UART、JTAG 引脚都是具体 `PACKAGE_PIN`。**更换板卡时必须自行修改 XDC 中的引脚与电平标准**，否则综合/实现可能报错或上板不工作。

### 使用 Zadig 绑定 WinUSB（一次性）

OpenOCD（JTAG 与复位）通过 libusb 访问 FT2232H，Windows 上需把 Channel A 绑定为 WinUSB 驱动。用 [Zadig](https://zadig.akeo.ie/) 操作一次即可，之后保持 WinUSB 无需再切换：

1. 下载并运行 Zadig（免安装绿色工具）。2. 菜单 **Options → List All Devices**，在下拉框选择 **Dual RS232-HS (Interface 0)**（VID:PID = `0403:6010`）。FT2232H 有两个接口，务必选 **Interface 0 / Channel A**。3. 右侧目标驱动选择 **WinUSB**（若已显示 WinUSB，说明已绑定，直接关闭即可）。4. 点击 **Replace Driver**，完成后在设备管理器确认 Channel A 显示为 WinUSB 设备。5. 重新插拔调试器（或重新枚举），确认 OpenOCD 可正常连接。

注意事项：
- 只改 FT2232H Channel A（`0403:6010` 接口 0）；**不要**给 CH340（`1A86:7523`，串口）换驱动，它保持 VCP 即可。
- Channel B（接口 1）本工程未使用，保持默认驱动。
- 与 Vivado Hardware Manager 冲突时，先关闭 `hw_server` 再使用 OpenOCD。
- 换电脑或驱动被改回 VCP 后，重复本流程即可。

### FPGA 复位（fpga_reset.py）

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

原理：FT2232H Channel A 提供 8 根通用 GPIO（ADBUS0~7），可设为 bit-bang（位带）模式，由软件逐位控制电平。复位用的是 **ADBUS5**（bit5 = 0x20），在 Sipeed RV-Debugger 上接到 FPGA 复位脚 `dbg_rst`（高有效）：写 `0x20` 拉高触发复位，写 `0x00` 释放。FPGA 端复位逻辑：`rst_async_n = sys_rst_n && (~dbg_rst) && clk_wiz_locked`。

### 程序烧录与串口工具

> ⚠️ DTR/RTS 不使用：串口保持默认电平直接打开，不要连接/翻转该模式；下载无响应时先运行 `kill_listener.ps1` 释放 COM 口。

**一键构建 + 运行（build_run.py）**——构建固件 → 复位 → 下载 → 监听输出，一条命令完成（SDK/ 目录下执行；参数透传 build.py 与 uart_send.py，详见 sdk.md）：

```bash
cd SDK
python tools/build_run.py demos/newlib/hello --newlib               # 构建 → 复位 → 下载 → 监听（空闲 3s 停）
python tools/build_run.py demos/rtthread --rtthread --idle-timeout 5
python tools/build_run.py demos/nolibc/breathing --no-listen        # 只下载不监听
```

**自动跑分（auto_coremark.py）**——复位 → UART 下载 → 等待运行 → 解析结果：

```bash
cd SDK

# 跑全部 9 个 CoreMark 配置（GCC Os/O1/O2/O3 + LLVM Oz/Os/O1/O2/O3）
python tools/auto_coremark.py

# 只跑单个配置：编译器 + 优化等级（如 GCC O2）
python tools/auto_coremark.py --compiler gcc --opt o2

# 只跑某个编译器的全部优化等级（如 LLVM/Clang）
python tools/auto_coremark.py --compiler clang

# 指定串口、波特率、uartbin 目录
python tools/auto_coremark.py --port COM8 --baud 115200
python tools/auto_coremark.py --data-dir <uartbin 文件目录>
```

**烧录 + 监听（uart_send.py）**——两种模式均实时打印：下载模式（发送 + 可选监听）与交互终端模式（`--interactive`，实时回显 + 键盘转发，`--no-echo` 关闭本地回显，Ctrl+C 退出）：

```bash
cd SDK

# 先复位再下载（推荐）；uartbin 默认在 test_data/soc/c 下查找，也可传完整路径
python tools/uart_send.py coremark_o2.uartbin --reset

# 仅下载（需提前手动复位）
python tools/uart_send.py coremark_o2.uartbin

# 指定串口
python tools/uart_send.py coremark_o2.uartbin --port COM8 --baud 115200

# 下载后监听：输出空闲 3 秒即停（--idle-timeout，默认 3s）；日志自动写入 logs/uart_send_<程序>_<时间戳>.log，可用 --log 指定
python tools/uart_send.py uart_echo_os.uartbin --reset --idle-timeout 3

# RT-Thread demo（--rtthread 构建产物）：t1/t2 双线程时间片轮转，持续交替打印，空闲 5 秒即停
python tools/uart_send.py rtthread_os.uartbin --reset --idle-timeout 5       # lts-v3.1.x（默认）
python tools/uart_send.py rtthread51_os.uartbin --reset --idle-timeout 5     # v5.1.0（--rtthread-version 51 构建）

# CoreMark 这类“中途静默、结尾有标志”的程序，可用 --until 精确停在标记末尾
python tools/uart_send.py coremark_o2.uartbin --reset --until "Correct operation validated."

# 交互终端：直接键入即发送（输入会本地回显，与板子输出以颜色区分），Ctrl+C 退出
python tools/uart_send.py --interactive --port COM8
```

**发送命令/文本（uart_cmd.py）**——向串口发送任意文本或原始字节，可选发送后监听：

```bash
cd SDK

# 发送文本（自动加换行）
python tools/uart_cmd.py "hello"

# 不加换行 / 发送原始十六进制字节 / 发送文件内容
python tools/uart_cmd.py "hello" --no-newline
python tools/uart_cmd.py --hex "AA BB CC 01"
python tools/uart_cmd.py --file cmd.txt

# 发送后监听响应：空闲 3 秒即停（--idle-timeout），或 --until 精确停在标记末尾；日志自动写入 logs/uart_cmd_<时间戳>.log
python tools/uart_cmd.py "hi" --idle-timeout 3
python tools/uart_cmd.py "hi" --until "Done!"
```

**接收输出（uart_recv.py）**——监听串口并实时打印，可用 `--output` 同时写入文件：

```bash
cd SDK

# 监听 30 秒（默认）
python tools/uart_recv.py

# 监听 60 秒 / 收到包含指定字符串后自动停止
python tools/uart_recv.py --timeout 60
python tools/uart_recv.py --until "CoreMark/MHz"

# 同时写入文件（覆盖；追加用 --append，静默用 --quiet）
python tools/uart_recv.py --output result.log
python tools/uart_recv.py --output log.txt --append --quiet
```

按 Ctrl+C 可随时中断。

### 典型组合用法

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
python tools/uart_send.py uart_echo_os.uartbin --reset --idle-timeout 3
python tools/uart_cmd.py "hi" --idle-timeout 3
```

> 注意：Windows 串口为独占访问，无法用两个进程同时收发。先启动 `uart_recv.py --output` 再发送会打不开端口；先发送完再启动监听则会丢掉程序开头的输出（`uart_recv` 打开时还会清空接收缓冲）。需要抓取运行输出的场景，请用上面的 `--idle-timeout`（输出空闲即停）或 `--until`（精确标记），或直接用 `auto_coremark.py`。

### 上板验证矩阵

前置：板卡烧录含调试子系统的 bitstream；FT2232H Channel A 绑定 WinUSB；JTAG 四线（TCK/TDI/TDO/TMS）+ GND，adapter speed 500kHz（杜邦线）。

| 测试 | 脚本 | 结果 |
|---|---|---|
| DMI 全功能 | `bd32_debug_test.cfg` | 通过 |
| 新功能测试 | `bd32_new_feat_test.cfg` | 通过 |
| SBA 外设总线 | `bd32_sba_periph.cfg` | 通过 |
| watchpoint | `bd32_watchpoint_test.cfg` | 通过 |
| GDB 在线 watchpoint | `run_gdb_watchpoint.bat`（管道模式） | PASS |
| GDB 套件 / demo | `run_gdb_debug_test.bat` / `run_demo_debug.bat`（socket） | PASS |
| CoreMark | `auto_coremark.py` | CRC 通过 |
| RT-Thread demo | `uart_send.py` 下载 + 串口监听 | lts-v3.1.x / v5.1.0 × ch32 / unified 四组合（lts-v3.1.x + picolibc 已上板验证），启动横幅 + t1/t2 持续轮转、无 SERR |
| uart_echo 全流程 | `uart_send.py` 下载 + 收发校验 | 下载 → 启动横幅 → 发送回显一致 → 回车打印 Done! |

### 板上长稳测试（soak）

RT-Thread 固件烧入后无人值守长跑，UART 监听器全程抓取输出判失败。**SERR**（system error）为检测到"同一条指令被写回两次"等系统级状态破坏时打印的错误标记，出现即失败：

| 脚本（`script/soc_test/`） | 作用 |
|---|---|
| `soak_start.bat <小时数>` | 启动后台串口监听，持续记录 UART 输出到 `logs/soak_uart.log` |
| `soak_report.bat` | 生成统计报告：t1/t2 打印计数、错误次数、通过结论 |
| `check_soak_proc.ps1` | 检查监听进程是否存活 |
| `kill_listener.ps1` | 结束监听并释放 COM 口（重新下载固件前必跑） |

- 判据：`logs/soak_uart.log` 中 t1/t2 持续交替、`SERR` 出现 0 次、`soak_SERR_FOUND.marker` 不存在；报告写入 `logs/soak_report.txt`。


## CoreMark 基准

CoreMark 源码位于 `SDK/demos/newlib/coremark/`，以 -O2 / -O3 编译（产物含优化等级后缀，避免相互覆盖）。`test_data/soc/c/` 中同时保留两套 .mem 文件，通过 `SoC_Config.sv` 的 `ITCM_FILE`/`DTCM_FILE` 切换。

预期正确输出（2K 规模，标准种子）：

```
CoreMark Size    : 666
seedcrc          : 0xe9f5
[0]crclist       : 0xe714
[0]crcmatrix     : 0x1fd7
[0]crcstate      : 0x8e3a
[0]crcfinal      : 0xe714
Correct operation validated
```

> 默认固件为 500 次迭代的 performance run（板上约 2.34s），仿真仅能观察到启动输出（`CoreMark running...`）；完整 CRC 校验以上板运行 `auto_coremark.py` 为准。

UART 配置机制：`soc_init()` 启动时通过 `mcycle` vs CLINT `mtime`（10ms 窗口）实测 CPU 主频并写入 `g_cpu_freq_hz`，`uart_init()` 用实测值计算 NCO 系数，不依赖编译期常量（测量失败才回退）——换主频后 UART 自动适应。

## Spike Diff-Test（差分测试）

使用 Spike ISA 模拟器作为黄金参考，与 RTL 仿真结果逐条对比写回序列，定位流水线功能 bug。

### 环境

建议在 WSL（或任意 Linux 环境）中通过发行版软件源安装 Spike 与 dtc，确保 `spike`、`dtc` 在 `PATH` 中；若为本地构建，将安装目录加入 `PATH` 即可。

### 运行 Spike 获取参考 trace

```bash
# WSL 中执行
spike --isa=rv32im -m0x10000:0x30000,0xe0010000:0x1000 \
  --log-commits <program>.elf 2> spike_trace.txt
```

参数说明：`-m` 指定内存区域（ITCM+DTCM 192KB，UART MMIO 4KB），`--log-commits` 输出每条指令的寄存器写回。

注意事项：
- 自定义 CSR（如 0xb06 性能计数器）会导致 Spike 触发 illegal instruction trap，trap 之前的 trace 仍然有效；
- 若固件含 UART polling 循环（等待 TX ready），Spike 会死循环，可用 ELF patch 将 polling 分支替换为 NOP（`0x00000013`）；
- WSL 输出为 UTF-16LE 编码，处理时需 `iconv -f UTF-16LE -t UTF-8`。

### 获取 RTL 写回 trace

在 vlog 编译时添加 `+define+WB_TRACE`，仿真结束后生成 `wb_trace.log`，格式为 `PC rd data`（十六进制 PC，十进制 rd，十六进制 data），记录 Port1（正常 WB）和 Port2（OITF 退休）的所有写回事件。

### 对比方法

1. **预处理**：流水线停顿可能让 RTL trace 连续多拍记录同一条写回，先去除重复项；2. **对齐**：RTL 会执行 BootROM 代码（Spike 不执行），需跳过 RTL trace 开头的 BootROM 指令；3. **匹配**：OITF 缓存长周期指令的结果，并在队列头部就绪后经 Port2 写回；Port1 与 Port2 的写回时序可能和 Spike 的提交记录不同，使用 lookahead 窗口（8~16 条）匹配；4. **定位**：首个无法匹配的写回可作为差异排查起点，后续差异可能由此传播。

### 典型调试流程

```
1. 复现：O2 通过 / O3 失败 → 确认是流水线冒险 bug
2. 静态分析：解析 objdump，找 MUL/DIV 的 RAW 依赖链
3. Trace 对比：Spike vs RTL 写回序列，定位第一个 divergence
4. 关联：将 divergence 对应的 PC 映射回反汇编，确认是哪条指令拿到错误值
```

## SVA 断言体系（L1/L2/L3）

按"局部不变式内联、跨模块检查 bind、分层宏使能"组织的仿真断言体系。

**分层与使能宏**：

| 层 | 使能方式 | 内容 |
|----|----------|------|
| L1 核心约定 | 常驻 | 各模块局部不变式，`a_` 前缀标签写在模块尾部断言区 |
| L2 模块级深化 | `+define+ASSERT_MODULE` | 覆盖清单全部 18 模块已铺满，入口零 SVA Error（见下） |
| L3 系统级检查 | `+define+ASSERT_SYS` | `rtl/assert/bind_core.sv`（中断接受双提交检测、退休唯一性）、`rtl/assert/bind_bus_timeout.sv`（双层超时衔接：主机强拆后桥有界回收） |

**文件组织**：局部不变式内联在各模块尾部统一断言区；跨模块/带状态检查放 `rtl/assert/`——`bind_core.sv`（L3，bind 到 RISC_V_Core：中断接受双提交检测、退休唯一性）、`bind_bus_timeout.sv`（L3，bind 到 SoC_top：双层超时衔接——主机强拆后桥侧有界回收/半事务不被叠加）、`bind_apb.sv`（bind 到 CLINT/PLIC/UART/TIMER/GPIO 五个从机的 APB 协议检查——SETUP→ACCESS 时序、等待期稳定、有界完成，L1 常驻；头部约定：只许加入编译全部从机的环境，核级 filelist 因此显式列 bind_core 而非 glob）。断言失败统一 `$error("[SVA][模块名]")` 前缀。

**覆盖清单**（L2 内联断言，共 18 个模块）：Pipeline_Ctrl（中断接受三约定）、CSR_Reg_Access（陷阱码检查 + 中断 mcause 编码）、Mem_Access（rvalid 端口稳定/仲裁互斥/拆分 FSM 4096 拍有界退出）、RegFile（x0 恒 0）、ID_EX/EX_MEM/MEM_WB（flush 清/stall 保持）、IFU_Buffer（16 位对齐/重定向清窗）、OITF、Zcmp_Expander（busy 语义）、DTCM（WRITE_FIRST 读回）、CLINT、AXI_Lite_Master（握手稳定性）、SoC_top（中断映射不变式）、APB_Master（双层超时衔接三约定）、Data_Hazard_Forward、plic_target、apb_uart（LSR/IIR 约定）。排除：BootROM（静态 ROM）、RVC_Expander（riscv-tests 覆盖）、clk_wiz（Xilinx IP）。

**回归判据**：run_all_custom_asm / run_all_riscv_tests 对 `Error: [SVA]` 优先判 FAIL（先于功能 PASS 判据），PASS 也说明 0 断言触发。

**运行入口**（SoC 级/系统级，不在核级清单）：L2 用 `script/core_test/sva_verify.do` 与 `script/soc_test/uart_lsr_verify.do`；L3 用 `script/soc_test/rtthread_sim_sys.do`。

**包化约定**：共享常量放 `rtl/pkg/BD32_Pkg.sv`（`bd32_pkg`），使用模块在 `module` 声明之前写文件级 `import bd32_pkg::*;`（模块内 import 覆盖不到端口）；包文件在所有 filelist/Vivado 工程中先于使用它的模块编译。

**APB 接口约定**：APB 总线走 `rtl/pkg/apb_if.sv`——主机端口 `apb_if.master m`（桥内 APB_Master/BFM），从机端口 `apb_if.slave s`（五个外设），监视用 `apb_if.mon`；互联对上游是 slave 视角、对下游是接口数组 `apb_if.master s[16]`（接口实例数组只允许常量下标，聚合经 generate 采集到线网数组后再多路选择）；接口实例必须带 `()`（`apb_if x;` 在 ModelSim 判为未知类型）且先声明后使用；APB 协议断言经 bind 挂进五个从机（bind 端口连接在目标作用域解析 `s.psel` 等）。

**AXI 接口约定**：AXI4 总线走 `rtl/pkg/axi_if.sv`（39 根信号）——Bus_Access/AXI_Lite_Master 为 `axi_if.master`（Bus_Access 是纯直通封装，内层实例直连端口 m），桥/err_slave 为 `axi_if.slave`，互联对上游 slave、对下游 m0/m1/m2 三个固定 master 视角；SoC_top 用 `axi_bus`/`axi_apb`/`axi_mrom`/`axi_ddr` 四个接口实例。**主机封装模块的陷阱**：接口直通封装（Bus_Access 类）删掉离散端口后必须同步把内层实例的连接改为 `.m(m)`，否则内层连接落到隐式线网上——ModelSim 编译静默放行（假绿），Vivado elaboration 才报 unconnected。

**写法约定**：带形式目标的模块里，仿真断言（`a_*` 前缀，完整 SVA 写法）只归 ModelSim 跑，形式断言（`fml_*` 前缀，Yosys SVA 子集写法）只归 SymbiYosys 跑，两套分开写、互不进对方工具；其余模块的断言只归 ModelSim，写法不限。Yosys 子集约束清单整理在 bd32-soc-workflow skill 的 Yosys SVA/RTL Subset Memo 节。

## 形式验证（SymbiYosys）

SVA 体系 P3：对关键模块做 BMC / 无界证明 / 覆盖率三合一形式验证。**六模块 16 任务全绿**（OITF / Mem_Access / AXI_Lite_Master / IFU_Buffer / Pipeline_Ctrl / CSR_Reg_Access，bmc depth30-40 + abc-pdr 无界证明 + cover 全命中；接口化与常量迁包后的 RTL 重新证明，cover 逐步到达核对非空洞），属性计划与完成记录见本章以下小节。

**包化/接口化后的 formal 运行约定**：三个恢复流（mem_access/ifu_buffer/axi_master）的 [script] 必须显式先读 `SoC_Config.sv` 与 `pkg/BD32_Pkg.sv`（sby 把 [files] 拷入 src/ 后 `include "./../.." 相对路径失效，define 不加载会导致接口成员隐式声明）；axi_master 另需先读 `pkg/axi_if.sv`（yosys 原生支持 interface 的扁平实例化连接）；axi_master_formal_top 以 axi_if 接口实例连接 DUT（成员无驱动 = 形式验证自由输入）。**勿用 sv2v 预处理 formal**：sv2v 把 `assert property` 静默转成空命名块（yosys 0 个 $assert 单元），PASS 全为空洞。

```bash
call D:\IC_Design_Toolkit\oss-cad-suite\environment.bat
cd /d Working\rtl\assert\formal
run_all_formal.bat                           # 六模块 bmc/prove/cover 一键全跑
sby -f oitf_formal.sby prove                 # 单模块单任务示例（prove）
```

要点：
- 必须经 `environment.bat` 启动（yosys 裸跑报 0xC0000139）；
- OITF.sv 存储为按字段并行数组（Yosys 不支持结构体数组的下标访问，会产生隐式 wire 静默失真）；
- 带形式目标的模块里，仿真断言（`a_*`，完整 SVA 写法）与形式断言（`fml_*`，Yosys 子集写法）成对分开写，各自留在对应工具里跑。

- DUT: `rtl/Core/OITF.sv`（4 深 FIFO，跟踪 MUL/DIV 长周期指令的乱序完成、顺序退休）
- 工具: SymbiYosys（BMC depth 30 + prove/k-归纳，引擎 abc pdr 与 smtbmc+yices 双跑）
- 环境: 输入全部自由穷举（无输入协议假设），仅约束复位时序——最大化极端输入组合的覆盖（wbck 无匹配条目、空 FIFO 退休、flush 与派发/退休同拍交织等均被穷举）

### 属性组（按 skill 优先级）

| 组 | 属性 | 优先级 | formal-ready |
|----|------|--------|--------------|
| A 复位 | 复位后 cnt=0、wr_ptr=rd_ptr=0、全条目 vld=0 | P1 | ✓ |
| B FIFO 序不变式（核心） | 环形序上 [rd_ptr, rd_ptr+cnt) 范围条目 vld=1 且范围外 vld=0；retire 头部清除、派发尾部置位后不变式保持 | P1 | ✓ |
| C 计数守恒 | cnt == vld 条目数；派发 +1 / 退休 -1 / flush 清零；cnt 永不超 DEPTH 不下溢 | P1 | ✓ |
| D 指针范围 | wr_ptr / rd_ptr 恒 < DEPTH | P1 | ✓ |
| E 冲刷 | flush 次拍 cnt=0 且 rd_ptr==wr_ptr 且全条目无效 | P1 | ✓ |
| F 退休合法性 | retire_valid ⇔ 头部条目 vld&&ready；cnt==0 时恒无 retire | P1 | ✓ |
| G RAW/WAW 停顿正确性 | oitf_stall ⟺ 派发阻塞（满/unit 忙）∨ RAW 命中 ∨ WAW 命中；命中解除当且仅当匹配条目退休 | P2 | ✓ |
| H 退休数据一致性 | retire_rd_data == 头部条目 result（结构性）；独立重算 wbck 匹配对照（影子重算） | P2 | ✓（影子版） |
| I 活性（最终完成） | 每条已派发指令最终退休（需要执行单元进度假设；BMC 不覆盖，可用 formal liveness 或仿真覆盖检查） | P3 | ✗ sim/cover |

### formal-ready 与 sim-only 的切分

- 全部 A-H 为安全属性（永真式），formal-ready ✓
- I 活性（每条已派发指令最终退休）需要执行单元进度假设，留给仿真 cover 检查。CoreMark 端到端运行属于仿真覆盖范围，形式验证不覆盖完整程序执行。

### 假设清单（全部可审计）

1. 复位时序：初始 1 拍 rst_n=0，此后恒 1（覆盖复位初始化属性组 A）2. **无输入协议假设**——lp_valid/wbck_valid/flush 全自由穷举 3. OITF 对"无匹配条目的 wbck_valid"按规格丢弃（flush 后单元残留完成），不设假设阻止此类输入

### 求解器与深度

- 引擎1: `abc pdr`（无需归纳不变式，对 FIFO 类设计极强）
- 引擎2: `smtbmc yices`（对照）
- depth: 30（4 深 FIFO 的填充/退休/flush 交错 ≈ 12 拍内全覆盖，30 拍含裕量）

### 验证结果

入口：`rtl/assert/formal/oitf_formal.sby`（bmc/prove/cover 三任务）+ `oitf_formal_top.sv` harness。运行方式（Windows 必须 cmd 环境）：

```bash
call D:\IC_Design_Toolkit\oss-cad-suite\environment.bat
cd /d Working\rtl\assert\formal
sby -f oitf_formal.sby                       # 三任务全跑；单任务加任务名后缀
```

| 任务 | 引擎 | 结果 |
|------|------|------|
| bmc depth 30 | smtbmc | **PASS**（假设检查 + 全部断言 30 拍无反例） |
| prove（无界） | abc pdr | **PASS**（PDR 自动归纳） |
| cover depth 30 | smtbmc | **PASS**，3/3 命中（full@6、retire∩flush@4、disp∩retire@4） |

## 回归建议

- 每次 RTL 改动：custom_asm + riscv-tests + tb_debug 全量回归 + 全部 demo + CoreMark + 上板串口验证。
- 每次固件改动：编译全部 demo + CoreMark（`SDK/tools/build.py`）+ 上板串口验证。
- 上板改动后：DMI / 新功能 / SBA / watchpoint / GDB 套件逐一回归。
- RT-Thread 改动（BSP/中断模式）：lts-v3.1.x / v5.1.0 × ch32 / unified 四组合仿真 + 上板。

## SDK Demos（可仿真 / 上板验证）

全部 demo 用 `SDK/tools/build.py` 编译（产物同步到 `test_data/soc/c/*.uartbin` 与 `.mem`），既可用于 ModelSim SoC 仿真（改 `SoC_Config.sv` 的 `ITCM_FILE`/`DTCM_FILE`），也可用 `uart_send.py --reset` 上板烧录。

### nolibc（裸机，无 C 库）

| demo | 验证内容 | 观察方式 |
|---|---|---|
| `empty` | 最小启动 + UART 输出 | 串口打印 |
| `blink` | GPIO 输出、CLINT mtime 延时 | LED 闪烁 |
| `breathing` | Timer PWM 呼吸灯 | LED 呼吸 |
| `gpio_input` | GPIO 输入、按键消抖轮询 | 按键控制 LED |
| `uart_echo` | UART TX/RX 全双工 | 串口回显 |
| `apb_timer_irq` | APB Timer 中断 | LED 按定时翻转 |
| `plic_irq` | PLIC 按键中断 | 按键进 ISR 翻 LED |
| `cpuinfo` | CSR 读写通路（mstatus/mtvec/mie…） | 串口 dump |
| `comprehensive_test` | 综合中断（定时器 + 按键） | 阶段 A/B 现象 |
| `bus_timeout` | 总线访问超时保护 | 异常处理打印 |
| `uart_irq` | UART 中断收发（RDA 收行 + THRE 回显） | 发 3 行即时回显 + PASS! |

### newlib-nano（精简 C 标准库）

| demo | 验证内容 |
|---|---|
| `hello` | printf/标准库启动 |
| `coremark` | 性能基准（CRC 校验，上板 `auto_coremark.py`） |
| `libc_test` / `stdio_test` / `stdlib_test` / `string_test` | libc 功能 |
| `math_test` | 数学库（软浮点） |
| `errno_test` | errno 机制 |

### RT-Thread（`--rtthread`）

| demo | 验证内容 |
|---|---|
| `rtthread` | 双线程时间片轮转（lts-v3.1.x，默认；`--irq-mode unified` 可切换统一入口中断模式） |
| `rtthread51` | 同上（v5.1.0，`--rtthread-version 51`） |

构建 + 上板示例（`build_run.py` 一键：构建 → 复位 → 下载 → 监听，SDK/ 目录下执行；仅构建用 `build.py`，见 sdk.md）：

```bash
cd SDK
python tools/build_run.py demos/nolibc/breathing                    # 裸机（LED 呼吸）
python tools/build_run.py demos/newlib/hello --newlib               # C 库（newlib-nano）
python tools/build_run.py demos/newlib/coremark --newlib --opt O3 --no-listen   # CoreMark -O3（跑分用 auto_coremark.py）
python tools/build_run.py demos/rtthread --rtthread                 # RT-Thread（默认 lts-v3.1.x）
```

## 附录：内存布局

```
BootROM:  0x0000_0000 ~ 0x0000_0FFF (4KB, 启动代码)
ITCM:     0x0001_0000 ~ 0x0001_FFFF (64KB, 代码段)
DTCM:     0x0002_0000 ~ 0x0002_FFFF (64KB, 数据段)
CLINT:    0xF200_0000  (APB PSEL[0])
PLIC:     0xFC00_0000  (APB PSEL[1])
GPIO:     0xE000_0000  (APB PSEL[2])
UART:     0xE001_0000  (APB PSEL[3])
Timer:    0xE002_0000  (APB PSEL[4])
SPI:      0xE003_0000  (APB PSEL[5], 预留)
I2C:      0xE004_0000  (APB PSEL[6], 预留)
Flash:    0x9000_0000  (AXI 从机, 未实现, 访问返回错误)
DDR:      0xB000_0000  (AXI 从机, 未实现, 访问返回错误)
```
