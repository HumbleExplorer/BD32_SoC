# OITF 形式验证属性计划（Property Plan）

- DUT: `rtl/Core/OITF.sv`（4 深 FIFO，跟踪 MUL/DIV 长周期指令的乱序完成、顺序退休）
- 工具: SymbiYosys（BMC depth 30 + prove/k-归纳，引擎 abc pdr 与 smtbmc+yices 双跑）
- 环境: 输入全部自由穷举（无输入协议假设），仅约束复位时序——最大化病理输入覆盖
  （wbck 无匹配条目、空 FIFO 退休、flush 与派发/退休同拍交织等均被穷举）

## 属性组（按 skill 优先级）

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
| I 活性 | 派发的指令最终退休（需要 unit 进度假设，BMC 不覆盖，formal liveness 或仿真覆盖） | P3 | ✗ sim/cover |

## formal-ready 与 sim-only 的切分

- 全部 A-H 为安全属性（永真式），formal-ready ✓
- I 活性（最终退休）需要 unit 进度假设，留给仿真 cover + fasttick 压测
- 仿真独有的值：CoreMark 端到端（真实程序下的组合爆炸，形式无法覆盖）

## 假设清单（全部可审计）

1. 复位时序：初始 1 拍 rst_n=0，此后恒 1（覆盖复位初始化属性组 A）
2. **无输入协议假设**——lp_valid/wbck_valid/flush 全自由穷举
3. 审计注记：OITF 对"无匹配条目的 wbck_valid"按设计丢弃（flush 后单元残留完成），此为规格行为，
   不添加假设阻止 solver 生成此类输入——若断言在该输入下失败即为真 bug

## 求解器与深度

- 引擎1: `abc pdr`（无需归纳不变式，对 FIFO 类设计极强）
- 引擎2: `smtbmc yices`（对照）
- depth: 30（4 深 FIFO 的填充/退休/flush 交错 ≈ 12 拍内全覆盖，30 拍含裕量）

## 落地结果（2026-09-14，P3 首战告捷）

入口：`rtl/assert/formal/oitf_formal.sby`（bmc/prove/cover 三任务）+ `oitf_formal_top.sv` harness。
运行方式（Windows 必须 cmd 环境）：

```bat
call D:\IC_Design_Toolkit\oss-cad-suite\environment.bat
cd /d Working\rtl\assert\formal
sby -f oitf_formal.sby            :: 三任务全跑；单任务加任务名后缀
```

| 任务 | 引擎 | 结果 |
|------|------|------|
| bmc depth 30 | smtbmc | **PASS**（假设检查 + 全部断言 30 拍无反例） |
| prove（无界） | abc pdr | **PASS**（PDR 自动归纳，0.23s；裸 k-induction 不可行——序不变式非一步归纳，勿回退 smtbmc prove） |
| cover depth 30 | smtbmc | **PASS**，3/3 命中（full@6、retire∩flush@4、disp∩retire@4） |

**属性修正记录**：序不变式首版 `ring_rel < cnt[ITAG_WIDTH-1:0]` 在 cnt==DEPTH（满）时低位截断误判为空，
BMC 第 6 步即出反例；改为与全宽 cnt 比较（零扩展）后全绿。教训：计数器比宽时勿截断 MSB。

**RTL 重构（三端等价）**：原 `oitf_entry_t` 结构体数组改为按字段并行数组
（cur_vld/cur_ready/cur_unit_id/cur_rd_addr/cur_rd_wen/cur_result + nxt_* 对应）。
原因见下节；ModelSim 全回归 + Vivado 综合语义不变（纯表示形式变换）。

## Yosys SVA/RTL 子集备忘（0.68+195 实测，写 formal 前必读）

1. **不支持结构体数组**：`struct_t arr[N]` 任何下标访问（含常数下标 + 字段选择）都会产生
   隐式 1-bit wire（静默失真，最危险）。存储一律用按字段并行数组。
2. **不支持模块级 `label: assert property (@(posedge clk) ...)`**——时钟必须来自外层
   `always @(posedge clk)`；`disable iff (!rst_n)` 改为 `if (rst_n)` 守卫。
3. **不支持 `|->` / `|=>`**——蕴含改写为 `if (A) assert property (B);`，次拍属性用
   `if ($past(A)) assert property (B);`。`$past`、`cover property`（always 内）可用。
4. generate 内断言不能带标签（展开重名），去标签用自动命名。
5. 文件级 `timeunit/timeprecision` 不支持（`ifndef FORMAL` 包裹）；`'{...}` 赋值模式、
   `automatic` 局部变量、genvar 位选 `[N:0]` 均不支持。
6. harness 的 DUT 输出必须显式声明（隐式 wire 会把多 bit 输出静默降为 1 bit）。

**Windows 运行环境坑**：①sby 读子进程输出按 UTF-8 解码，cmd 的 GBK 消息会触发
UnicodeDecodeError 崩溃——已在 `oss-cad-suite\share\yosys\python3\sby_core.py:295` 的
decode 加 `errors="replace"` 补丁（工具升级后需重打）；②yosys.exe 必须经
`environment.bat` 启动（直接跑报 0xC0000139 DLL 入口错误）；③Git Bash 里 sby/yosys
的参数转义不可靠，复杂命令写 .bat 或 .ys 脚本执行。

## 追加教训（2026-09-18，pipeline_ctrl/csr formal + 三审计缺陷修复）

- **harness 放开自由输入 = 推平一层遮蔽**：异常码从钉哨兵改为自由后，逐层
  暴露缺口——①欠约束假失败（自由 31 位码产生“bit30=0 但 get_priority 落
  默认 15”的非法组合，需按生产者契约补分阶段合法码 assume）→ ②复位拍假
  反例（assume 按惯例 `if(rst_n)` 门控，复位拍无约束，组合输出断言必须补
  rst_n 守卫）→ ③遮蔽谓词缺口（WFI 分支优先级高于 trap 接受，推迟一拍接受，
  fml_accept_unshadowed 漏 `(waiting_int && ~ex_access_en)`）。每层反例都是
  一次精确的设计语义提问，逐层修到绿。
- **Yosys 不支持 `inside`**：约束集合要写成显式相等或链（与 0.68+195 备忘
  同族）。
- **无时钟 assert property 在 formal 下逐评估点检查**：Pipeline_Ctrl 的
  fml_a_* 故意不带时钟（组合输出契约），复位拍一样被查——凡“工作态才
  有意义”的组合契约一律加 rst_n 守卫。
- **遮蔽谓词完整性论证法**：把 flush 大 always_comb 的分支优先级链完整列出，
  逐分支对照遮蔽谓词——凡“先于被检分支、且改变 flush 输出”的分支都必须
  在谓词里。漏分支 = 遮蔽拍假失败（本次 WFI）。
- **leaf-module harness 的契约方向**：下游模块 formal 不重证生产者契约，
  用 assume 承接（如 CSR 的 trap→码非哨兵由 pipeline_ctrl formal 负责），
  断言升级为对自身逻辑有约束力的检查（如 mcause_n=={1'b0,码} 组成）。
