# 验证方法

## 仿真（ModelSim，无需板子）

| 套件 | 顶层 | 运行 | 判定 |
|---|---|---|---|
| custom_asm | tb_core_top | `script/run_all_custom_asm.py` | 每项输出 pass/fail |
| riscv-tests | tb_core_top | `script/run_all_riscv_tests.py` | 通过（fence_i/ma_data 未过） |
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

- 不支持自修改代码（FENCE.I 不刷新取指路径）与非对齐访存。
- 无 ProgBuf / Debug ROM；抽象内存访问未实现（走 SBA）。
- 单 hart；无跟踪调试。

## 回归建议

- 每次 RTL 改动：custom_asm + riscv-tests + tb_debug 全量回归。
- 每次固件改动：编译全部 demo + CoreMark（`SDK/tools/build.py`）+ 上板串口验证。
- 上板改动后：DMI / 新功能 / SBA / watchpoint / GDB 套件逐一回归。
