# 验证方法

> 说明：`test_data/` 下的 `.dat` / `.elf` / `.dump` 均为构建产物，新克隆环境先获取 riscv-tests 源码（见 [SDK 构建工具与协议](sdk.md)）并运行 `SDK/tools/build_riscv_tests.py` 与 `test_data/custom_asm/build_asm.py`，再执行以下回归。

## 仿真（ModelSim，无需板子）

| 套件 | 顶层 | 运行 | 判定 |
|---|---|---|---|
| custom_asm | tb_core_top | `script/run_all_custom_asm.py` | 每项输出 pass/fail |
| riscv-tests | tb_core_top | `script/run_all_riscv_tests.py` | 50/50 全过（含 fence_i / ma_data） |
| Debug 模块 | tb_debug | `script/debug_test/run_msim_debug.bat` | 通过 |
| 外设 | tb_apb_* | `script/xxx_test/top_tb.bat` | 通过 |
| SoC | tb_soc_top | `run 55ms`（CoreMark 启动） | 启动输出通过 |

说明：
- ModelSim 路径通过 `MODELSIM_PATH` 环境变量或脚本默认值配置。
- 回归输出统一写入仓库根 `logs/`。
- 核级测试判定约定：x26=1 完成、x27=1 通过、x3(gp) 记录失败子测试编号。

## 上板（JTAG / UART）

| 测试 | 脚本 | 结果 |
|---|---|---|
| DMI 全功能 | `bd32_debug_test.cfg` | 通过 |
| 新功能专项 | `bd32_new_feat_test.cfg` | 通过 |
| SBA 外设总线 | `bd32_sba_periph.cfg` | 通过 |
| watchpoint | `bd32_watchpoint_test.cfg` | 通过 |
| GDB 在线 watchpoint | `run_gdb_watchpoint.bat`（管道模式） | PASS |
| GDB 套件 / demo | `run_gdb_debug_test.bat` / `run_demo_debug.bat`（socket） | PASS |
| CoreMark | `auto_coremark.py` | CRC 通过 |

前置：板卡烧录含调试子系统的 bitstream；FT2232H Channel A 绑定 WinUSB；
JTAG 四线（TCK/TDI/TDO/TMS）+ GND，adapter speed 500kHz（杜邦线）。

## 已知限制

- 自修改代码（FENCE.I）与非对齐访存已支持（分别对应 `rv32ui-p-fence_i` / `rv32ui-p-ma_data`）。
- 无 ProgBuf / Debug ROM；抽象内存访问未实现（走 SBA）。
- 单 hart；无跟踪调试。

## 回归建议

- 每次 RTL 改动：custom_asm + riscv-tests + tb_debug 全量回归。
- 每次固件改动：编译全部 demo + CoreMark（`SDK/tools/build.py`）+ 上板串口验证。
- 上板改动后：DMI / 新功能 / SBA / watchpoint / GDB 套件逐一回归。

## SDK Demos（可仿真 / 上板验证）

全部 demo 用 `SDK/tools/build.py` 编译（产物同步到 `test_data/soc/c/*.uartbin`
与 `.mem`），既可用于 ModelSim SoC 仿真（改 `SoC_Config.sv` 的
`ITCM_FILE`/`DTCM_FILE` 指向对应 `.mem`），也可用 `uart_send.py --reset` 上板烧录。

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

### newlib（C 标准库）

| demo | 验证内容 |
|---|---|
| `hello` | printf/标准库启动 |
| `coremark` | 性能基准（CRC 校验，上板 `auto_coremark.py`） |
| `libc_test` / `stdio_test` / `stdlib_test` / `string_test` | libc 功能 |
| `math_test` | 数学库（软浮点） |
| `errno_test` | errno 机制 |

构建示例：

```bash
cd SDK
python tools/build.py demos/nolibc/breathing          # 裸机
python tools/build.py demos/newlib/hello --newlib      # C 库
python tools/build.py demos/newlib/coremark --newlib --opt O3  # CoreMark -O3
```

上板烧录示例：

```bash
python SDK/tools/uart_send.py test_data/soc/c/breathing.uartbin --reset
```
