# Changelog

本项目遵循[语义化版本](https://semver.org/lang/zh-CN/)。首个正式版本发布时开始记录。

## [Unreleased] — 计划 v1.0.0

### 修复

- **中断接受拍边界指令双重提交（tidle SERR）**：中断接受拍冲刷集原为 IF_ID+ID_EX（EX_MEM 不冲），边界指令的 EX 结果泄漏进 EX_MEM 完成第一次写回，mret 后又按 mepc 重执行（第二次提交）——非幂等指令（`addi s0,s0,1768`）状态双重累加，RT-Thread tidle 周期性 SERR。现中断接受拍补冲 EX_MEM（更老指令提交不受影响），边界指令单次重执行。
- **异常优先级表缺项**：`get_priority` EX 级未登记未对齐访存码（4/6），导致未对齐陷阱携带全 1 哨兵码（`mcause=0x7FFFFFFF, mepc=0`）且 `mtval` 丢失；已补登记并按 `[3:0]` 切片比较。
- **CLINT SVA 编译坏点**：断言引用不存在的 `clk/rst_n`，改为端口名 `PCLK/PRESETn`。
- **ITCM FPGA 地址打拍回退**：曾对 BRAM `addra` 打拍以收敛时序，但写使能仍为组合信号（wea/addra 错拍，store 写错地址）且取指整体晚一拍破坏取指窗口配对；XILINX-only 分支仿真回归覆盖不到，回退并留注释。

### 变更

- **CPU 频率 75MHz → 62.5MHz**：Zcmp 取指窗口重构后关键路径（EX 访存地址 → trigger → 中断冲刷 → ITCM 写口，约 15ns）决定 62.5MHz 为可签核最高频点；clk_wiz 及 SDK/testbench 频率常量同步。62.5MHz 下 WNS +0.171 全 MET。
- 中断接受与 WFI/总线等待窗口的交互加固：WFI 冻结让位在途访存、DTCM 端口地址保持、rvalid 停顿释放拍放行提交。
- 板级 `sys_clk` IBUF 隔离 + `IS_GLOBAL_CLOCK` 约束（修复 clk_wiz 端口非法连接）。

### 新增

- **OITF 形式验证（SymbiYosys P3）**：`rtl/assert/formal/`（oitf_formal.sby 三任务 + harness）；BMC depth30 / abc-pdr 无界证明 / cover 3/3 全 PASS。OITF 断言组 B/C/D/E/F/G/H 全部获得数学证明（序不变式、计数守恒、指针范围、flush 语义、退休合法性与数据一致性、停顿一致性），输入全自由穷举仅约束复位时序。
- OITF 存储表示拍平重构：结构体数组 → 按字段并行数组（Yosys 不支持结构体数组的任何下标访问，会产生隐式 wire 静默失真）；语义等价，ModelSim/Vivado/Yosys 三端共用。
- 断言专项 formality 工具链：OSS CAD Suite（yosys 0.68/sby/yices/abc）；`doc/property_plan_oitf.md` 新增落地结果与 Yosys SVA 子集备忘。
- 修复 core_test filelist 连带编译 bind_apb.sv（核级环境无 APB 从机，bind 目标缺失必报错）；soc/debug filelist 重复 glob 去重。
- RT-Thread tick 压力复现脚本 `rtthread_sim_fasttick.do`（35.7MHz 快速 tick）与故障窗口分析链 `rtthread_sim_fail_trace.do` + `parse_fail_window.py`（延迟 dump 绕开 VCD 1GB 截断）。
