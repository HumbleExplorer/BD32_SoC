# Changelog

本项目遵循[语义化版本](https://semver.org/lang/zh-CN/)。首个正式版本发布时开始记录。

## [Unreleased] — 计划 v1.0.0

### 修复

- **UART16550 九项行为修复（TB 全寄存器套件 24 用例补全暴露）**：① FCR[1]/[2] 清 FIFO 未实现——清位自清零但从未驱动 FIFO 清空，`sync_fifo` 增加 `flush` 端口（清空优先于同拍读写）直连；② MSR 寄存器未驱动（读回 X）——无调制解调器引脚，恒 0（IIR 的 MSR 子源编码保留不产生中断）；③ PE 奇偶校验极性反——TX 发奇校验 `~parity_calc` 而 RX 判错条件与正确帧一致（正确帧必报错、坏帧不报），RX 报错条件取正确帧之反；④ FE 帧错误判定不可达——停止位非高时 FSM 提前退出 RX_STOP，到不了 cnt15 判定点；⑤ rx_valid_o 多拍写 FIFO 风险（④连带，收敛为停止位采样点单拍）；⑥ RBR 空读返回未初始化 FIFO mem 的 X——空读返回 0；⑦ `download_done` 含 `|| ~download_en` 使 DBG_STAT 未使能时恒 1——仅 NORMAL_MODE 置位；⑧ IIR 超时码 1/64 拍闪断软件不可观测——新增 `tout_int` 锁存至数据活动（读 RBR/新字节/FIFO 空）；⑨ RX 5/6/7 位数据对齐——移位寄存器把数据收在高位而 TX 发低位，round-trip 不成立，`rx_o` 右对齐（16550 语义）。修复后 uart_test 24 用例、uart_irq SoC 收发测试、全回归 10/10 步、8x 长流全字比对、板上 uart_irq + CoreMark 长流全部 PASS。
- **uart_rx 长流相位回归（修复④⑤时的第一版引入，bus_timeout 复验暴露）**：为达④删掉停止位槽"rx 提前变低即退出"，丢失背靠背连续帧的相位重新对齐（新帧网格从真实边沿起算），长流 31160 bit 下相位逐帧漂移 → 偶发字节错位 + 帧边界漏写 → 下载 FSM 卡死（`download_done` 不置位，bus_timeout 卡 `wait`）。修复：恢复提前退出但加 `bit_val` 多数判决门控（`~rx_low && bit_val` 才认下一帧起始沿；FE 帧整槽低 bit_val=0 不被误判为起始沿，留在槽内等 cnt15 报 FE），FE 判定改 `sample_cnt>=12 && bit_val==0`（投票窗完成后多数判决）。方法论：`tb_uart_dl_file`（8 倍速 + 真实 uartbin 全字比对，秒级）+ `git show HEAD` 旧 RTL A/B 对照 + 逐文件 bisect 定位 uart_rx.sv；stream/mini 两测试并入外设回归补"下载路径常态覆盖"缺口。
- **bus_timeout 测试两处陈旧**：mepc 期望 0x105bc→0x10638（固件重建后布局漂移，out.dump 逐字确认新址即故障 store）；run 窗口 300→400ms（uartbin 增至 3116B，下载需 270.5ms + 30ms 判定窗口，原 300ms 恰好截断判定行）。修后四要素全中 TEST PASSED。

- **BTB 半字对齐索引混叠 + req_fwd 恢复指针陈旧（形式验证定位）**：① BTB index/tag 均弃 PC bit1，跨字 jal 的 PC 与对齐 PC 混叠同一条目致永久 miss、每次 EX 重定向罚 ~3 拍——index 扩为 pc[8:1]（含半字位），tag 保持 pc[15:9] 自然排除，target 数组随之 15 位；② IFU_Buffer Zcmp capture 收尾按"活 have_cur"而非恢复态选路，且以 fetch_addr 为恢复基准——req_fwd 前推使活 req_addr 领先 fetch_addr 后，consume 恢复出落后 2 字的请求指针（fml_a_window_pair 反例定位），改为恢复态持有窗口字时取 `restore_req_addr = 窗口字+4`、无窗口字时以活 req_addr 为基准。修复后 formal 六模块 bmc/prove/cover 全 PASS。
- **取指跨字 32 位指令结构性停顿（req_fwd 预取前推 v1+v2）**：v1 refill_now 消费拍请求指针即时前推至消费字+4，消除"消费与请求争同一字"的 2 拍气泡；**v2（2026-09-20）扩展到 crossing 换装拍**（`+ (~zcmp_capture & ~zcmp_active) & can_issue & crossing & next_ready`，zcmp 门控防冻结期地址口污染恢复流）。fml_a_zcmp_freeze 放宽 req_fwd 检查、fml_a_req_next_word 约定演进。**板级（62.5MHz，同 uartbin 对比）**：v1 6 配置 C 扩展 ticks -3.3%~-5.1%、fetch 停顿 -35%~-53%；21 配置全矩阵扩展税 -13.4%→-6.4%；**v2 全矩阵复测（21 配置，板上，62.5MHz）**：体积纯赚 23~33% `.text`（全扩展最优 GCC-Os -32.7%、picolibc -27.7%、gcc-O2 -29.5%）；性能近免费——21 格中 13 格 ticks 不变或更快，C gcc-O2 再 **-8.7%**（fetch 停顿 -73%、占比 12%→3.6%）、C+B+Zicond LLVM-Os-picolibc **+3.6%（最大正收益）**、全扩展 LLVM-Os-picolibc 反超无扩展 **+1.4%**；唯一明显负贡献 C+Zcmp（~+4%，cm 展开税，pico fetch 停顿 7.19M 全场最高）；none 双线逐位不变证明零副作用。旧"全扩展净损失 -7%"（v1 口径）被推翻。板上连测后 FPGA 挂死用 **JTAG 重烧比特流**恢复（裸 DTR/RTS 复位无效）。归因仿真 fetch_wait -92.7%（198,449→14,560 拍）。RV32C 在 BD32 上已成近纯收益；剩余停顿为重定向落跨字的 1 拍结构性下限。
- **SVA 2026-09-16 审计三缺陷（2620562）**：CSR 全 1 标记断言常量位宽错（30 位零扩展对真全 1 标记 31'h7FFFFFFF 永真漏报）；apb_uart LSR 断言 NBA 寄存器与当拍组合态直比（THRE/TEMT 翻转必假失败，改 $past 并发断言）；两个 formal harness 异常码钉全 1 标记使异常路径断言空转（放开为自由输入 + 分阶段合法码约束 + WFI 遮蔽谓词补全，异常优先级表/全 1 标记/冲刷级映射升为无界真实证明）。
- **HPM 计数语义三 bug（5170922）**：MULDIV/minstret 漏计 OITF 退休（乘除走 port2 写回、主 WB 影子被 RAW 停顿重派发冲掉，漏计 ~70%，改 OITF 退休拍计数）；mcounterclr 写后锁存把计数器永久钉 0（改单拍脉冲）；csrw 0xBC0 因读译码缺项误判非法指令（补读回条目）。minstret 同拍双退休双增量。
- **Zcmp ret 预测/RAS 漂移（0c6420c）**：popret 退休拍 pc mux 配对修正（formal 补冻结期属性）；预测器 spec 更新挂 spec_upd 门控。板上预测率 +1.7~3.5pp（口径修正后复测与基线一致）。

- **中断接受拍边界指令双重提交（tidle SERR）**：中断接受拍冲刷集原为 IF_ID+ID_EX（EX_MEM 不冲），边界指令的 EX 结果泄漏进 EX_MEM 完成第一次写回，mret 后又按 mepc 重执行（第二次提交）——非幂等指令（`addi s0,s0,1768`）状态双重累加，RT-Thread tidle 周期性 SERR。现中断接受拍补冲 EX_MEM（更老指令提交不受影响），边界指令单次重执行。
- **异常优先级表缺项**：`get_priority` EX 级未登记未对齐访存码（4/6），导致未对齐陷阱携带全 1 标记码（`mcause=0x7FFFFFFF, mepc=0`）且 `mtval` 丢失；已补登记并按 `[3:0]` 切片比较。
- **CLINT SVA 编译坏点**：断言引用不存在的 `clk/rst_n`，改为端口名 `PCLK/PRESETn`。
- **ITCM FPGA 地址打拍回退**：曾对 BRAM `addra` 打拍以收敛时序，但写使能仍为组合信号（wea/addra 错拍，store 写错地址）且取指整体晚一拍破坏取指窗口配对；XILINX-only 分支仿真回归覆盖不到，回退并留注释。

### 变更

- **HPM 计数器地址规范化（0c6420c，固件可见接口变更）**：CSR 地址从自定义 0xBC3-0xBC8 重映射到标准地址 **mhpmcounter3-17 = 0xB03-0xB11**；计数门控改由 **mcountinhibit(0x320)** 承担（复位即全计数，软件按需停，三写路径：BootROM 不再写/mode 寄存器/CSR 指令），BootROM 移除 csrw 0x306（该 CSR 已不存在，写入即非法指令）；新增 load-use/OITF/取指停顿周期计数器 **0xB0F-0xB11**（counter15-17）；mhpmevent3-11 WARL；misa=RV32IMCB(0x40001106)。旧固件若仍访问 0xBC3-0xBC8 需重建。
- **`.xpr` churn 收拢（A+B 双管齐下）**：① A：`BD32_SoC/BD32_SoC.xpr` 还原为干净历史形态 + 唯一实质改动 `impl_1 LaunchOptions -jobs 4`（原 109c1a4 混入的 130 行 Vivado 报告配置重序列化噪声全部剥除，`StratHandle/ReportStrategy` 回紧凑形态）；② B：新增 `SDK/tools/xpr_normalize.py`（幂等规范化器：剥 `<ReportConfig>` 块 + 空展开元素折叠为自闭合 + 多空白行折叠，`--check`/`--install-hook` 两模式，路径限定仓库子树）+ pre-commit 钩子自动规范化 staged `.xpr`——**约定：Vivado 保存过 `.xpr` 后提交前跑一次 `python SDK/tools/xpr_normalize.py`（装了钩子则自动），保持 `.xpr` diff 永远干净可读**。副作用说明：剥除报告自动配置后个别自动 .rpt 在下次 Vivado 打开保存前可能不生成，不影响综合/实现/比特流。
- **CPU 频率 75MHz → 62.5MHz**：Zcmp 取指窗口重构后关键路径（EX 访存地址 → trigger → 中断冲刷 → ITCM 写口，约 15ns）决定 62.5MHz 为可签核最高频点；clk_wiz 及 SDK/testbench 频率常量同步。62.5MHz 下 WNS +0.171 全达标。
- 中断接受与 WFI/总线等待窗口的交互加固：WFI 冻结让位在途访存、DTCM 端口地址保持、rvalid 停顿释放拍放行提交。
- 板级 `sys_clk` IBUF 隔离 + `IS_GLOBAL_CLOCK` 约束（修复 clk_wiz 端口非法连接）。
- **uart_send 0 字节"静默拒收"问题修复 + 日志路径越界防护**：`--early-warn`（默认 6s）——监听阶段持续 0 字节超阈值打印**一次**非致命诊断（区分"板子挂死→JTAG 重烧"与"固件↔比特流不匹配→重建 uartbin"，并给判别法），不再静默等满 `--timeout`；0 字节结束态改报明确诊断而非笼统 "sent successfully"。`log_path` 写入前统一走 `is_inside_repo` 子树校验（默认文件名 stem 做 `._-` 白名单净化），`args.log` 入口 `safe_log_path` 致命校验——杜绝日志写逃出仓库。**旧 uartbin 静默拒收根因确认（遗留问题关闭）**：确诊为 **09-16 前固件的编译期 FCW 波特率常数**（老主频假设）vs 新比特流主频不一致；`mrom.s`（运行时测主频 + NCO FCW 自适应 + 存 0x0002FFF0）与 bsp v2（`g_cpu_freq_hz` 运行时 + `soc_init` ±10% 合理性钳制）已在**两端**消除该问题——**当前构建的 uartbin 不会因频率不一致再被静默拒收**；当前唯一 0 字节来源=**板子挂死**（JTAG 重烧恢复，09-20 实证），已由上条 early-warn 明确区分。

### 新增

- **AXI/APB 总线验证资产补全（AXI 互联链验证 + 下载路径常态覆盖）**：① `tb/axi_lite_bfm.sv`——AXI4-Lite master BFM（端口与生产 AXI_Lite_Master 的 m_* 一致，AW/W 同拍发起、AW 超时短路、各通道握手超时保护）；② `tb/tb_axi_interconnect.sv` + `script/axi_test/`——全真实 DUT 链验证（互联 → AXI_APB_Bridge → APB 互联挂 apb_slave_stub 桩从机 / axi_err_slave×2），7 用例：APB 回环 OKAY、随机等待态反压数据完整、PSLVERR→SLVERR 传播、err 段 OKAY+读0、从机挂死→桥超时 SLVERR 有界、未路由段 BFM 有界超时；已并入 `run_all_verification.bat` 第 5/7 步，verification_plan 的"AXI DECERR/SLVERR 传播"PLANNED 项完成为 PASS；③ `tb/tb_uart_dl_file.sv`（8 倍速 + 真实 uartbin 全字比对）与 `tb_uart_dl_mini.sv`（20B 最小包）并入 `run_periph_regression.bat`（外设回归扩为六项）——补上"UART 下载路径无常态覆盖"的结构性缺口。
- **uart_irq demo（UART 中断收发测试）+ TB 完整流程**：`SDK/demos/nolibc/uart_irq`（RDA 收行 + THRE 回显，IIR 四类子源按读清约定处理，收尾顺序=处理→清源→Complete 对齐 PLIC 约定）；tb_soc_top `UART_IRQ_TEST` 流程 + `script/soc_test/run_uart_irq.do`；**仿真与上板双 PASS**（板上发 3 行即时回显 + PASS!）。
- **UART TB 全寄存器套件（tb_apb_uart 重写，4→24 用例）**：全寄存器复位值/RW 回环/DLAB 分组复用/掩码/FCW + IIR 五子源（RDA/超时/THRE/RLS/MSR）+ LSR 四位错误（OE/PE/FE/BI 全路径，PE 覆盖偶/奇/强制三模式对帧与错帧）+ FCR 触发级 1/4/8/14 与清 FIFO + DBG 通道 + 中断优先级 + 5/6/7 数据位（RX 右对齐）+ 两位停止位 8N2；run.do 8ms。对齐 GPIO/timer 的完善度，是 UART 九项修复的检出手段。
- **板上工具补全**：`SDK/tools/bd32_uart_dl_diag.cfg`（UART 下载状态一键取证：MODE_SEL/DBG_STAT/LSR/ITCM 头字/mtime 五件套）；`SDK/tools/board_uart_irq_test.py`（uart_irq 上板一键判定）；`script/soc_test/fetch_timing.do`（取指时序图取材，先跑 20ms 再开 VCD 抓内核中段）。**取指时序图真实化**：`fetch_timing_redirect_crossword` 按真实仿真波形重画（全量 f_wait 分类实证"剩余停顿=重定向落跨字 1 拍"），信号名全 RTL 英文真名并补 `pc` 请求行。
- **doc/spec.md 权威规格**：10 章（存储器映射/时钟树/复位树/中断映射/五组寄存器表含复位值与访问类型/模块层级/错误处理），数值全部 RTL 实读；总线错误模型三分法写实（err 段恒 OKAY+读0、APB 空槽聚合默认值 OKAY、未路由段总线超时 DECERR）。
- **交互式 SoC 组件架构图（doc/bd32_soc_architecture.html）**：archify 生成的自包含交互 HTML——五级流水主路径 + BPU/OITF/CSR 侧支 + BootROM/ITCM/DTCM/APB 外设存储区，附取指连续化三件套/预测体系/验证基线三张结论卡片；规格源 `bd32_soc_architecture.arch.json`（showcase 质量档 9/9 检查 + 浏览器四视口 containment/readability 全过），`doc/architecture.md` 概览处链接，更新流程见文中说明。**附取指逐拍时序图 ×2**（wavedrom 渲染，`fetch_timing_redirect_crossword` 重定向落跨字的结构性 1 拍下限、`fetch_timing_reqfwd_v2` v1/v2 crossing 场景对比，WaveJSON 源 `.json5` 随库可重渲染），`doc/architecture.md` 取指节内嵌。
- **update_mrom 一键更新工具链（b688d1f）**：`update_mrom_build.bat`（gcc 完整链接 mrom.s → mrom.elf + objdump 未解析跳转检查）→ `update_mrom.py`（解析 ELF → verify() 强校验 0x306 引用必须为 0 / 切进 ELF 头 → 生成 mrom.dat + mrom.coe，`--emit-tcl` 生成 mrom IP 重综合 tcl）→ `update_mrom_synth.bat`（reset_target + generate_target + 显式重跑 mrom_synth_1，解决 Vivado 感知不到 COE 变化的坑）。
- **HPM 双层审计框架（e4b003f）**：`script/run_hpm_audit.py`——TB 参考模型独立译码 + 同沿双快照逐项核对（11 项精确相等），配 hpm_audit_test 微基准；改 HPM/CSR RTL 必跑。stall_test 停顿计数器/MULDIV 仿真回归入库（5170922 配套）。
- **形式验证扩展至四模块全绿（1db9199）**：Mem_Access（拆分 FSM 有界完成 + rvalid 提交门）、AXI_Lite_Master（FSM 合法 + 有界超时逃逸 + 握手稳定性）、IFU_Buffer（取指窗口簿记不变式）三任务全 PASS，入口 `rtl/assert/formal/run_all_formal.bat`；SoC_Config 形式下 BUS_TIMEOUT 缩参（机制验证与标定分离）。
- **IFU_Buffer Zcmp 恢复路径窗口污染修复（1db9199，形式验证定位的真 bug）**：字内前半字 cm.push capture 漏锁存 restore_cur_w/cur_w_addr，consume 恢复陈旧值致取指流错位；capture 分支补锁存。RTL 三端兼容化改写（Zcmp 函数 return→函数名赋值、IFU 变量基址 part-select→显式 mux）。
- **SVA 断言体系 L1/L2/L3（26e44a8 / 3cc2d03 / 99231ce / 01b26b9）**：分层宏（L1 常驻 / ASSERT_MODULE / ASSERT_SYS）；17 个 RTL 文件内联断言（中断接受三约定、陷阱码检查、rvalid 端口稳定、x0 恒 0、流水线寄存器 flush/stall 约定、IFU 对齐与清窗、OITF 计数/flush、Zcmp busy 语义、DTCM WRITE_FIRST 等）；`bind_apb.sv` 五从机 APB 协议检查；`bind_core.sv` 系统级双提交检测 + 退休唯一性（SERR 防护检查）；回归脚本对 `** Error: [SVA]` 优先判 FAIL。
- **板上 soak 长稳工具（917a0fd / 77d181f / 020ee01）**：UART 监听 + SERR marker + 8 点报告；12 小时 110 万行 t1/t2 交替 0 SERR 基线；CH340 DTR 双向约束坑位记录。
- **OITF 形式验证（SymbiYosys P3）**：`rtl/assert/formal/`（oitf_formal.sby 三任务 + harness）；BMC depth30 / abc-pdr 无界证明 / cover 3/3 全 PASS。OITF 断言组 B/C/D/E/F/G/H 全部获得数学证明（序不变式、计数守恒、指针范围、flush 语义、退休合法性与数据一致性、停顿一致性），输入全自由穷举仅约束复位时序。
- OITF 存储表示拍平重构：结构体数组 → 按字段并行数组（Yosys 不支持结构体数组的任何下标访问，会产生隐式 wire 静默失真）；语义等价，ModelSim/Vivado/Yosys 三端共用。
- 断言形式验证工具链：OSS CAD Suite（yosys 0.68/sby/yices/abc）；`doc/property_plan_oitf.md` 新增验证结果与 Yosys SVA 子集备忘。
- 修复 core_test filelist 连带编译 bind_apb.sv（核级环境无 APB 从机，bind 目标缺失必报错）；soc/debug filelist 重复 glob 去重。
- RT-Thread tick 压力复现脚本 `rtthread_sim_fasttick.do`（35.7MHz 快速 tick）与故障窗口分析链 `rtthread_sim_fail_trace.do` + `parse_fail_window.py`（延迟 dump 绕开 VCD 1GB 截断）。
