# Changelog

本项目遵循[语义化版本](https://semver.org/lang/zh-CN/)。首个正式版本发布时开始记录。

## [Unreleased] — 计划 v1.0.0

### 修复

- **BTB 半字对齐索引混叠 + req_fwd 恢复指针陈旧（形式验证定位）**：① BTB index/tag 均弃 PC bit1，跨字 jal 的 PC 与对齐 PC 混叠同一条目致永久 miss、每次 EX 重定向罚 ~3 拍——index 扩为 pc[8:1]（含半字位），tag 保持 pc[15:9] 自然排除，target 数组随之 15 位；② IFU_Buffer Zcmp capture 收尾按"活 have_cur"而非恢复态选路，且以 fetch_addr 为恢复基准——req_fwd 前推使活 req_addr 领先 fetch_addr 后，consume 恢复出落后 2 字的请求指针（fml_a_window_pair 反例实锤），改为恢复态持有窗口字时取 `restore_req_addr = 窗口字+4`、无窗口字时以活 req_addr 为基准。修复后 formal 六模块 bmc/prove/cover 全 PASS。
- **取指跨字 32 位指令结构性停顿（req_fwd 预取前推）**：refill_now 消费拍请求指针即时前推至消费字+4，消除"消费与请求争同一字"的 2 拍气泡；fml_a_zcmp_freeze 断言补 req_fwd 前推豁免。**2026-09-19 板级 6 配置 A/B 实测（62.5MHz，500 轮，重建固件 vs 09-18 基线）**：C 扩展配置 ticks -3.3%~-5.1%（gcc-O2 C -5.1%、gcc-O2 full -4.7%、llvm-Os C -3.3%、llvm-Os full -4.2%），fetch 停顿计数 -35%~-53%（full llvm-Os 18.7M→8.7M）；无扩展对照 +1.5%~1.7%（指令流 0.00% 差异，为重建二进制布局漂移噪声底，校准后 C 配置真实收益 ≈-5%~-7%）。性能损失口径更新：LLVM Os 全扩展净损失 -7% → 约 -2.5%。
- **SVA 2026-09-16 审计三缺陷（2620562）**：CSR 哨兵断言常量位宽错（30 位零扩展对真哨兵 31'h7FFFFFFF 永真漏报）；apb_uart LSR 断言 NBA 寄存器与当拍组合态直比（THRE/TEMT 翻转必假失败，改 $past 并发断言）；两个 formal harness 异常码钉哨兵使异常路径断言空转假绿（放开为自由输入 + 分阶段合法码约束 + WFI 遮蔽谓词补全，异常优先级表/哨兵/冲刷级映射升为无界真实证明）。
- **HPM 计数语义三 bug（5170922）**：MULDIV/minstret 漏计 OITF 退休（乘除走 port2 写回、主 WB 影子被 RAW 停顿重派发冲掉，漏计 ~70%，改 OITF 退休拍计数）；mcounterclr 写后锁存把计数器永久钉 0（改单拍脉冲）；csrw 0xBC0 因读译码缺项误判非法指令（补读回条目）。minstret 同拍双退休双增量。
- **Zcmp ret 预测/RAS 漂移（0c6420c）**：popret 退休拍 pc mux 配对修正（formal 补冻结期属性）；预测器 spec 更新挂 spec_upd 门控。板上预测率 +1.7~3.5pp（口径修正后复测与基线一致）。

- **中断接受拍边界指令双重提交（tidle SERR）**：中断接受拍冲刷集原为 IF_ID+ID_EX（EX_MEM 不冲），边界指令的 EX 结果泄漏进 EX_MEM 完成第一次写回，mret 后又按 mepc 重执行（第二次提交）——非幂等指令（`addi s0,s0,1768`）状态双重累加，RT-Thread tidle 周期性 SERR。现中断接受拍补冲 EX_MEM（更老指令提交不受影响），边界指令单次重执行。
- **异常优先级表缺项**：`get_priority` EX 级未登记未对齐访存码（4/6），导致未对齐陷阱携带全 1 哨兵码（`mcause=0x7FFFFFFF, mepc=0`）且 `mtval` 丢失；已补登记并按 `[3:0]` 切片比较。
- **CLINT SVA 编译坏点**：断言引用不存在的 `clk/rst_n`，改为端口名 `PCLK/PRESETn`。
- **ITCM FPGA 地址打拍回退**：曾对 BRAM `addra` 打拍以收敛时序，但写使能仍为组合信号（wea/addra 错拍，store 写错地址）且取指整体晚一拍破坏取指窗口配对；XILINX-only 分支仿真回归覆盖不到，回退并留注释。

### 变更

- **CPU 频率 75MHz → 62.5MHz**：Zcmp 取指窗口重构后关键路径（EX 访存地址 → trigger → 中断冲刷 → ITCM 写口，约 15ns）决定 62.5MHz 为可签核最高频点；clk_wiz 及 SDK/testbench 频率常量同步。62.5MHz 下 WNS +0.171 全 MET。
- 中断接受与 WFI/总线等待窗口的交互加固：WFI 冻结让位在途访存、DTCM 端口地址保持、rvalid 停顿释放拍放行提交。
- 板级 `sys_clk` IBUF 隔离 + `IS_GLOBAL_CLOCK` 约束（修复 clk_wiz 端口非法连接）。

### 新增

- **形式验证扩展至四模块全绿（1db9199）**：Mem_Access（拆分 FSM 有界完成 + rvalid 提交门）、AXI_Lite_Master（FSM 合法 + 有界超时逃逸 + 握手稳定性）、IFU_Buffer（取指窗口簿记不变式）三任务全 PASS，入口 `rtl/assert/formal/run_all_formal.bat`；SoC_Config 形式下 BUS_TIMEOUT 缩参（机制验证与标定分离）。
- **IFU_Buffer Zcmp 恢复路径窗口污染修复（1db9199，形式验证定位的真 bug）**：字内前半字 cm.push capture 漏锁存 restore_cur_w/cur_w_addr，consume 恢复陈旧值致取指流错位；capture 分支补锁存。RTL 三端兼容化改写（Zcmp 函数 return→函数名赋值、IFU 变量基址 part-select→显式 mux）。
- **SVA 断言体系 L1/L2/L3（26e44a8 / 3cc2d03 / 99231ce / 01b26b9）**：分层宏（L1 常驻 / ASSERT_MODULE / ASSERT_SYS）；17 个 RTL 文件内联断言（中断接受三契约、陷阱码哨兵、rvalid 端口稳定、x0 恒 0、流水线寄存器 flush/stall 合同、IFU 对齐与清窗、OITF 计数/flush、Zcmp busy 语义、DTCM WRITE_FIRST 等）；`bind_apb.sv` 五从机 APB 协议检查；`bind_core.sv` 系统级双提交哨兵 + 退休唯一性（SERR 疫苗）；回归脚本对 `** Error: [SVA]` 优先判 FAIL。
- **板上 soak 长稳工具（917a0fd / 77d181f / 020ee01）**：UART 监听 + SERR marker + 8 点报告；12 小时 110 万行 t1/t2 交替 0 SERR 基线；CH340 DTR 双向约束坑位记录。
- **OITF 形式验证（SymbiYosys P3）**：`rtl/assert/formal/`（oitf_formal.sby 三任务 + harness）；BMC depth30 / abc-pdr 无界证明 / cover 3/3 全 PASS。OITF 断言组 B/C/D/E/F/G/H 全部获得数学证明（序不变式、计数守恒、指针范围、flush 语义、退休合法性与数据一致性、停顿一致性），输入全自由穷举仅约束复位时序。
- OITF 存储表示拍平重构：结构体数组 → 按字段并行数组（Yosys 不支持结构体数组的任何下标访问，会产生隐式 wire 静默失真）；语义等价，ModelSim/Vivado/Yosys 三端共用。
- 断言专项 formality 工具链：OSS CAD Suite（yosys 0.68/sby/yices/abc）；`doc/property_plan_oitf.md` 新增落地结果与 Yosys SVA 子集备忘。
- 修复 core_test filelist 连带编译 bind_apb.sv（核级环境无 APB 从机，bind 目标缺失必报错）；soc/debug filelist 重复 glob 去重。
- RT-Thread tick 压力复现脚本 `rtthread_sim_fasttick.do`（35.7MHz 快速 tick）与故障窗口分析链 `rtthread_sim_fail_trace.do` + `parse_fail_window.py`（延迟 dump 绕开 VCD 1GB 截断）。
