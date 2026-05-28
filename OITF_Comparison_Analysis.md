# BD32 vs E203 OITF 深度对比分析

## 概述

E203 (Hummingbirdv2) 的 OITF 是为 **2 级流水线**设计的通用长指令跟踪 FIFO，支持 LSU、MULDIV、NICE 等多个长流水单元。BD32 OITF 是为 **4 级流水线**定制的、只针对 MULDIV 的简化实现。

---

## 1. OITF Entry 结构对比

### E203 (`e203_exu_oitf.v`)

| 字段 | 位宽 | 说明 |
|------|------|------|
| `vld_r[i]` | 1 bit | 条目有效 |
| `rdwen_r[i]` | 1 bit | 是否写寄存器堆 |
| `rdfpu_r[i]` | 1 bit | 是否浮点寄存器堆写 |
| `rdidx_r[i]` | `RFIDX_WIDTH` | 目标寄存器索引 |
| `pc_r[i]` | `PC_SIZE` | 指令 PC（用于异常追踪） |

**E203 不存储结果数据！** 结果的写回由各长流水单元自己通过 `e203_exu_longpwbck.v` 的仲裁逻辑完成。

### BD32 (`OITF.sv`)

| 字段 | 位宽 | 说明 |
|------|------|------|
| `vld` | 1 bit | 条目有效 |
| `rd_addr` | `REG_ADDR_WIDTH` | 目标寄存器索引 |
| `rd_wen` | 1 bit | 是否写寄存器 |
| `ready` | 1 bit | 结果已就绪（等退休） |
| `result` | `DATA_WIDTH` | 乘法/除法结果 |

### 关键差异

1. **结果存储位置不同**：
   - E203：结果不存入 OITF，而是由 `longpwbck` 仲裁后直接写回寄存器堆。
   - BD32：结果存入 OITF 条目内（`result` 字段），退休时由 OITF 自己写回。

2. **E203 存储 PC** 用于异常上报时的精确异常 PC。BD32 未存储 PC。

3. **E203 不做 `ready` 标记**：E203 通过 itag 匹配来判断结果就绪（哪个 itag 的结果到达 = 哪个条目完成），而 BD32 通过 `ready` 标记位 + FIFO 顺序退休。

4. **E203 额外跟踪 `rdfpu`**：区分整数/浮点寄存器堆，BD32 无此需求。

---

## 2. Dispatch & Stall 逻辑对比

### E203 (`e203_exu_disp.v`)

E203 在 dispatch 模块中做全面的依赖检查：

```verilog
// RAW 依赖：dispatching 指令的 rs1/rs2/rs3 与 OITF 中未完成的长指令的 rd 匹配
wire raw_dep = oitfrd_match_disprs1 | oitfrd_match_disprs2 | oitfrd_match_disprs3;

// WAW 依赖：当前指令目标 rd 与 OITF 中任何未完成长指令的 rd 匹配
wire waw_dep = oitfrd_match_disprd;

wire dep = raw_dep | waw_dep;

// dispatch condition 汇总
wire disp_condition =
    (disp_csr ? oitf_empty : 1'b1)       // CSR 需等 OITF 空
  & (disp_fence_fencei ? oitf_empty : 1'b1) // FENCE 需等 OITF 空
  & (~wfi_halt_exu_req)                   // WFI halt
  & (~dep)                                 // RAW + WAW 依赖
  & (disp_alu_longp_prdt ? disp_oitf_ready : 1'b1); // 长流水需 OITF 就绪
```

**关键点**：
- **RAW** 检查 `rs1`, `rs2`, `rs3`（FPU 的 rs3）。
- **WAW** 检查 `rd`，防止 ALU 指令写回的 rd 覆盖尚未完成的长流水指令的 rd。
- E203 中有 `alu_to_oitf WAW` 问题的详细注释（`e203_exu_disp.v:153-175`）：ALU 指令可能超前于 OITF 长指令写回同一个 rd，产生 WAW 冲突。
- **E203 的依赖性检查是对 ALL 指令生效的**（不区分是否长流水），通过 `disp_condition` 控制 `disp_i_ready` 和 `disp_i_valid_pos`，实现全局流水线停顿。

### BD32 (`OITF.sv`)

```verilog
// RAW 依赖检查
rs1_match[j] = oitf_mem[j].vld & oitf_mem[j].rd_wen
             & (oitf_mem[j].rd_addr == check_rs1_addr) & ~oitf_mem[j].ready;
rs2_match[j] = ... // 同上

raw_hazard = (~is_muldiv_id) & ((check_rs1_valid & rs1_hit) | (check_rs2_valid & rs2_hit));

// Stall 条件 = 新 MULDIV 无法发射 或 非 MULDIV 遇到 RAW
assign oitf_stall = (is_muldiv_id & (~mul_div_ready | full)) | raw_hazard;
```

**关键差异**：

| 维度 | E203 | BD32 |
|------|------|------|
| RAW 检查 | `rs1` + `rs2` + `rs3` (FPU) | `rs1` + `rs2` |
| WAW 检查 | **有** (`oitfrd_match_disprd`) | **无** |
| per-instruction stall | `disp_condition` 每条指令判断 | `oitf_stall` 全局停顿 |
| ready 条件 | 不检查 ready（结果不在 OITF 内） | 检查 `~oitf_mem[j].ready`（RAW 只关心未就绪的） |
| Stall 范围 | ALU + 非 ALU 都可能有依赖 | `raw_hazard` 只针对非 MULDIV 指令 |

**BD32 缺少 WAW 检查是一个潜在问题**：
- 场景：MUL x3, x1, x2（长流水，写入 x3）已经 dispatch 并挂起在 OITF 中 → 紧接着 ADD x3, x4, x5（ALU，也写 x3）可能比 MUL 更早写回 → WAW 冲突。
- 但是 BD32 是 4 级流水线加 in-order commit，如果 MULDIV 结果通过 OITF 退休，且退休优先级高于 ALU 写回，则可以避免 WAW。需要仔细确认。

---

## 3. Writeback / Retirement 对比

### E203 写回流程

E203 的写回是 **三阶段协作**：

```
长流水单元 (LSU/MULDIV/NICE)
    │ wbck_i_valid + wbck_i_itag + wbck_i_wdat
    ▼
e203_exu_longpwbck (仲裁)
    │ 检查 itag == oitf_ret_ptr
    │ 是 → 接受该单元的写回
    │
    ├─→ longp_wbck_o_valid → 写到寄存器堆 (regfile)
    ├─→ oitf_ret_ena      → OITF 弹出顶部
    └─→ longp_excp_o_valid → 异常提交（如有）
```

关键代码 (`e203_exu_longpwbck.v:88-92`)：
```verilog
wire wbck_ready4lsu = (lsu_wbck_i_itag == oitf_ret_ptr) & (~oitf_empty);
wire wbck_sel_lsu = lsu_wbck_i_valid & wbck_ready4lsu;
```

**特点**：
- 通过 **itag 精确匹配** 来决定哪个长流水单元的结果可以退休。
- 退休的是 OITF 顶部条目（`oitf_ret_ptr`），保证 **in-order 写回**。
- 长流水单元的 `ready` 反馈是：
  ```verilog
  lsu_wbck_i_ready = wbck_ready4lsu & wbck_i_ready;
  ```
  只有当该单元的 itag 匹配 OITF 顶部 AND 写入下游 ready 时，才真正完成握手。
- 结果数据不经过 OITF，直接从长流水单元通过 `longp_wbck` 仲裁发送到寄存器堆。

### BD32 写回流程

```
mul_div 单元
    │ mul_div_valid + mul_div_result
    ▼
OITF 内部
    │ 匹配 wr_ptr（当前写入位置）
    │ 存入 result 字段
    │ 标记 ready = 1
    ▼
OITF 退休
    │ oitf_mem[rd_ptr].vld & .ready & wb_idle
    │
    └─→ retire_valid → 写回寄存器堆
```

关键代码 (`OITF.sv:140-143`)：
```verilog
if (mul_div_valid && (ITAG_WIDTH'(i) == wr_ptr)) begin
    oitf_nxt[i].ready  = 1'b1;
    oitf_nxt[i].result = mul_div_result;
end
```

**特点**：
- OITF 自身存储结果，退休时直接输出。
- 顺序退休（FIFO 顶部先出）。
- 需要额外 `wb_idle` 握手信号等待 WB 阶段空闲。

### 对照

| 维度 | E203 | BD32 |
|------|------|------|
| 结果存储位置 | 长流水单元持有，不存 OITF | OITF 内部存储 |
| 退休触发 | itag 匹配 `oitf_ret_ptr` | FIFO 顶部 `rd_ptr` 的 `ready` |
| 多源写回 | `longpwbck` 仲裁 LSU+NICE（+MULDIV 间接） | 单源（MULDIV 只写一个条目） |
| 写回顺序 | In-order（itag = ret_ptr） | In-order（FIFO 顺序） |
| 异常处理 | 长流水异常通过 `longp_excp_o` 上报 | 无异常处理 |

---

## 4. itag 管理对比

### E203 itag 流程

```
1. Dispatch (e203_exu_disp.v:245):
   disp_oitf_ena = disp_o_alu_valid & disp_o_alu_ready & disp_alu_longp_real;

2. OITF 分配 itag (e203_exu_oitf.v:126):
   dis_ptr = alc_ptr_r;
   → 发射给 ALU 时携带: disp_o_alu_itag = disp_oitf_ptr  (e203_exu_disp.v:249)

3. ALU 传递给长流水单元 (e203_exu_alu_muldiv.v:46):
   input muldiv_i_itag

4. 长流水单元输出时携带 itag:
   通过 LSU/MULDIV 的 wbck 接口携带 itag 回到 longpwbck

5. longpwbck 匹配:
   wbck_ready4xxx = (xxx_wbck_i_itag == oitf_ret_ptr) & (~oitf_empty);
```

整个流程中 itag 是显式传递的：
- **分配**: OITF 生成 `dis_ptr` → dispatch 赋值给 `disp_o_alu_itag`
- **传递**: ALU → 解码 → 分发给 long-pipe 单元 → 单元携带 itag 输出
- **回收**: `longpwbck` 比较 `lsu_wbck_i_itag == oitf_ret_ptr`

### BD32 itag 使用

BD32 的 itag 是**隐式**的，基于 wr_ptr 的位置：

```verilog
// 写入时：使用 wr_ptr 作为位置
if (disp_fire && (ITAG_WIDTH'(i) == wr_ptr)) begin
    oitf_nxt[i].vld = 1'b1;
    ...
end

// 结果就绪时：同样使用 wr_ptr
if (mul_div_valid && (ITAG_WIDTH'(i) == wr_ptr)) begin
    oitf_nxt[i].ready  = 1'b1;
    oitf_nxt[i].result = mul_div_result;
end
```

### 关键差异

| 维度 | E203 | BD32 |
|------|------|------|
| itag 显式性 | 显式 tag，通过 pipeline 传递 | 隐式，基于 wr_ptr 位置 |
| 多条目支持 | 支持，每个长流水单元携带自己的 itag | 只支持 **单个** MULDIV |
| itag 分配/回收 | alloc_ptr / ret_ptr 独立管理 | wr_ptr / rd_ptr，顺序推进 |
| back2back 支持 | 支持（多个 div/mul 同时在不同阶段） | **不支持**（必须等前一个结果就绪才能 dispatch 下一个） |

### BD32 的问题

BD32 的 `wr_ptr` 用于结果匹配时，存在严重 Bug：

```verilog
// 问题：当 disp_fire 后 wr_ptr 会递增
if (disp_fire) begin
    wr_ptr_nxt = wr_ptr + 'h1;  // wr_ptr 指向下一个空位
    cnt_nxt    = cnt + 'h1;
end

// 但结果就绪时仍用 wr_ptr 匹配
if (mul_div_valid && (ITAG_WIDTH'(i) == wr_ptr)) begin
    oitf_nxt[i].ready = 1'b1;  // 这指向的是 "下一个" 空位，不是刚写入的！
end
```

**这是错误**：`mul_div_valid` 时 `wr_ptr` 已经指向下一个空条目了，所以结果会被标记到**错误的条目**上。

**正确做法**：
1. 方案 A：在指令 dispatch 时给每个条目存储一个显式 itag，mul_div 返回时携带 itag。
2. 方案 B：改为用 `disp_itag` 信号（即 dispatch 时的 `wr_ptr`），在多周期后 `mul_div_valid` 时进行匹配。
3. 方案 C（最简单）：对于单 issue MULDIV，直接用 rd_ptr（FIFO 底部）匹配，即 `mul_div_valid` 时标记 `oitf_nxt[rd_ptr].ready = 1`——因为单 issue 时 rd_ptr 就是当前正在执行的那条指令。

此外，由于 `mul_div_valid` 可能在 `disp_fire` 之后很多周期才到达（甚至下一个 mul_div 可能已经 dispatch），此时 `wr_ptr` 已经变了，结果匹配完全错误。

---

## 5. Pipeline Integration 对比

### E203 集成方式

E203 的 OITF 是**集中式**的依赖检查中心：

```
Decoder/ID
    │ disp_i_valid
    ▼
e203_exu_disp ←→ e203_exu_oitf (依赖检查 + itag 分配)
    │
    ├── disp_o_alu_valid → ALU (所有指令都走 ALU)
    │   ├── short-pipe → ALU 直接完成
    │   └── long-pipe  → 分发到 LSU / MULDIV / NICE
    │                      │
    │                      └─→ wbck interface → e203_exu_longpwbck
    │                                             │
    │                                             └─→ oitf_ret_ena (退休)
    └── disp_i_ready (stall feed-back)
```

**停顿是 per-instruction 粒度的**：
- `disp_condition` 对每条指令单独判断。
- 如果当前指令有依赖 → 该指令停顿，但后续无依赖的指令可能可以 dispatch（虽然 E203 的 in-order 2 级流水线不允许乱序发射）。

### BD32 集成方式

```
Decoder (inst_type)
    │ inst_type = 3'd6 (MULDIV)
    ▼
OITF.sv (依赖检查)
    │ oitf_stall
    ▼
Pipeline_Ctrl
    │ 全局停顿 (pc_stall, if_id_stall, id_ex_stall, ex_mem_stall, mem_wb_stall 全部 stall)
    ▼
mul_div 单元 (Executer 内)
    │ mul_div_valid + mul_div_result
    ▼
OITF.sv (结果收束 + 退休)
    │ retire_valid
    ▼
RISC_V_Core (wback mux)
```

**停顿是全局的**：
```verilog
// Pipeline_Ctrl.sv:180
else if (waiting_int || ~bus_access_ready || oitf_stall) begin
    pc_stall        = 1'b1;
    if_id_stall     = 1'b1;
    id_ex_stall     = 1'b1;
    ex_mem_stall    = 1'b1;
    mem_wb_stall    = 1'b1;
end
```

### 对照

| 维度 | E203 | BD32 |
|------|------|------|
| Stall 粒度 | per-instruction | 全局 |
| 分发策略 | 所有指令经 ALU，长流水 OITF 跟踪 | inst_type 区分，MULDIV 走 OITF |
| 独立单元数 | LSU, MULDIV, NICE（多个） | 只有 MULDIV |
| 流向 | OITF ←→ Dispatch → ALU → LongPipe → longpwbck → OITF | OITF ← mul_div_unit |

---

## 6. Flush / Exception 处理对比

### E203 Flush 支持

E203 的 MULDIV 单元接收单独的 `flush_pulse` 信号：

```verilog
// e203_exu_alu_muldiv.v:50
input  flush_pulse,

// 内部使用（e203_exu_alu_muldiv.v:88-93）
wire flushed_r;
wire flushed_set = flush_pulse;
wire flushed_clr = muldiv_o_hsked & (~flush_pulse);

// 状态机每个状态都可以被 flush 触发退出
assign state_exec_exit_ena = muldiv_sta_is_exec & ((...) | flush_pulse);
assign state_exec_nxt = flush_pulse ? MULDIV_STATE_0TH : ...;
```

**但 E203 的 OITF 本身没有显式的 flush 端口**。flush 只影响到 MULDIV 单元内部的状态机重置。OITF 条目的清理是通过退休（`oitf_ret_ena`）完成的——当一条 MULDIV 被 flush 时，它不会产生有效的结果写回，因此其 OITF 条目不会被退休（会一直卡住？）。

等等，实际上 E203 的 OITF 没有 flush 是因为：如果 mul/div 被 flush，`muldiv_o_valid` 不产生，`muldiv_o_ready` 不握手，该条目的 `vld` 标记永远不会被清除——这是另一个潜在问题。查看 E203 的 `e203_exu_longpwbck.v`，退休也是靠 OITF `ret_ptr` 匹配 itag，同样不会被 flush 清除。

但 E203 有 **WFI halt 机制**：`wfi_halt_exu_ack = oitf_empty`，说明 WFI 会等 OITF 变空。

### BD32 Flush

BD32 **完全没有 flush 支持**：
- `OITF.sv` 没有 `flush` 输入。
- 如果发生 trap/异常/flush，OITF 中的条目不会被清除。
- 退休逻辑继续等待 `wb_idle` + `ready`，但在 flush 后这些结果不应被写回。

### 讨论

**对于 MULDIV**：
- 理论上 mul/div 指令不产生异常，所以不需要因自身异常而 flush。
- 但外部 flush（如中断、fence.i）可能导致：MULDIV 已 dispatch、结果尚未完成时，流水线被冲刷。
  - E203：MULDIV 内部状态机被 `flush_pulse` 重置，但结果在被丢弃前可能产生错误的状态。
  - BD32：无 flush → 旧的 MULDIV 结果可能错误地退休并写回寄存器堆。

**风险等级**：
- 对于简单的 FPGA 验证环境，flush 场景很少发生。
- 对于产品级处理器，缺少 flush 支持是一个不足。

---

## 总结表

| 维度 | E203 (`e203_exu_oitf`) | BD32 (`OITF.sv`) | 差距 |
|------|------------------------|------------------|------|
| **Entry 结构** | vld, rdwen, rdfpu, rdidx, pc | vld, rd_addr, rd_wen, ready, result | E203 不存结果，BD32 存结果但不存 PC |
| **RAW 检查** | rs1 + rs2 + rs3 + ready-aware | rs1 + rs2 + ready-aware | BD32 无 rs3（不需 FPU），OK |
| **WAW 检查** | **有** | **无** | **潜在 bug** |
| **结果存储** | 不存 OITF，由 longpwbck 仲裁 | OITF 内部存储 | 设计选择不同 |
| **itag 管理** | 显式传递（分配→传递→回收） | 隐式 wr_ptr | BD32 **wr_ptr 结果匹配有 Bug** |
| **Multi-entry** | 支持多个 in-flight MULDIV | **只支持 1 个** | 单 issue 限制，但匹配逻辑错误 |
| **Stall 粒度** | per-instruction | 全局 | 全局停顿浪费性能 |
| **Flush 支持** | MULDIV 有 `flush_pulse` | **无** | 异常/中断可能残留错误结果 |
| **多源支持** | LSU + MULDIV + NICE | 仅 MULDIV | BD32 不需要多源 |
| **异常追踪** | 存储 PC，通过 longpwbck 上报 | 无 | mul/div 不产生异常，影响小 |
| **退休策略** | itag 匹配 OITF top，顺序退休 | FIFO 顺序，ready 标记 | 类似，但 E203 更严格 |
| **FENCE/FENCEI** | 检查 `oitf_empty` | 未实现 | 可能缺少 |

---

## 需要修复/改进的问题

### 严重 (Bug)

1. **Result 匹配逻辑错误** (`OITF.sv:140`)
   ```verilog
   // 当前代码 (错误)：
   if (mul_div_valid && (ITAG_WIDTH'(i) == wr_ptr)) begin
       oitf_nxt[i].ready = 1'b1;
       oitf_nxt[i].result = mul_div_result;
   end
   ```
   - `wr_ptr` 在 `disp_fire` 后已经递增，指向下一个空条目。
   - 如果 OITF 中有多个条目（如深度 4），`mul_div_valid` 时 `wr_ptr` != 之前 dispatch 的那条。
   - **修复方案（单 issue）**：由于只有一个 MULDIV in-flight，应改为匹配 `rd_ptr`：
     ```verilog
     if (mul_div_valid && (ITAG_WIDTH'(i) == rd_ptr)) begin
         oitf_nxt[i].ready  = 1'b1;
         oitf_nxt[i].result = mul_div_result;
     end
     ```

2. **缺少 WAW 检查**
   - 建议增加 `rd_match` 检查类似 E203：
     ```verilog
     assign rd_match[j] = oitf_mem[j].vld
                        & oitf_mem[j].rd_wen
                        & (oitf_mem[j].rd_addr == disp_rd_addr);
     assign waw_hazard = |rd_match & disp_rd_wen;
     ```
   - 加到 `oitf_stall` 条件中。

### 中等 (功能缺失)

3. **缺少 Flush 支持**
   - 添加 `flush` 输入，flush 时清除所有 OITF 条目：
     ```verilog
     if (flush) begin
         for (int i = 0; i < OITF_DEPTH; i++)
             oitf_nxt[i] = '0;
         wr_ptr_nxt = '0;
         rd_ptr_nxt = '0;
         cnt_nxt = '0;
     end
     ```

4. **FENCE/FENCEI 缺少 OITF_empty 检查**
   - 当执行 `fence` 或 `fence.i` 指令时，应等待 `oitf_empty`。
   - 参考 E203 的 `disp_condition`。

### 低优先级 (优化)

5. **全局停顿 → per-instruction 停顿**
   - 当前 `oitf_stall` 会停住整个流水线，包括与 MULDIV 无关的指令。
   - 优化：仅对有 RAW 依赖的指令停顿，其他指令正常流动。
   - 但这需要更复杂的流水线控制（non-blocking stall per stage）。

6. **OITF 条目存储 PC**
   - 如果将来需要支持精确异常（如在长流水期间发生的总线异常），需要存储 PC。
   - 当前 MULDIV 不产生异常，故优先级低。

7. **多源长流水支持**
   - 如果需要支持 LSU（load/store miss）做长流水 → 需要类似 E203 的显式 itag 机制。
