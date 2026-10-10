// ==========================================================================
// OITF —— Outstanding Instruction Tracking FIFO
// 跟踪已发射但未完成的长周期指令，使流水线在等待结果时不阻塞后续
// 无依赖的 ALU 指令。结果就绪后按 FIFO 顺序退休写回寄存器堆。
//
// 设计要点：
//   · 派发（EX 阶段）：检测到长指令时检查 RAW，无冲突则入队
//   · 写回匹配：unit_wbck_valid 触发时，从 rd_ptr 扫描找该 unit 最
//     老的未就绪条目标记 ready（同 unit 顺序完成，无需 itag 传递）
//   · 退休：FIFO 头部条目 ready 且 vld 则退休，写回寄存器堆
//   · 两种停顿：①RAW(EX) ②WAW(EX)（双写端口，无需写回冲突停顿）
//
// 通用化：NUM_LP_UNITS 控制长周期硬件单元数量。
// 当前 2（MUL=0, DIV=1），加 FPU 只需增大参数并连好信号。
//
// 【存储表示说明】条目状态用「按字段拆分的并行数组」表示
// （cur_vld/cur_unit_id/... 而非 struct 数组）。原因：Yosys（形式验证
// 端）不支持结构体数组的任何下标访问（常数/变量下标都会产生隐式
// wire）；拍平表示在 ModelSim/Vivado/Yosys 三端语义一致。
// ==========================================================================
`include "./../SoC_Config.sv"
`ifndef FORMAL
timeunit 1ns;
timeprecision 1ps;
`endif
module OITF #(
    parameter OITF_DEPTH     = 4,
    parameter DATA_WIDTH     = `DATA_WIDTH,
    parameter REG_ADDR_WIDTH = `REG_ADDR_WIDTH,
    parameter NUM_LP_UNITS   = 2,                // 长周期单元数（MUL=0, DIV=1）
    localparam UNIT_ID_W     = $clog2(NUM_LP_UNITS),
    localparam ITAG_WIDTH    = $clog2(OITF_DEPTH)
)(
    input   logic                               clk,
    input   logic                               rst_n,
    // EX 阶段指令信息
    input   logic                               lp_valid,
    input   logic   [UNIT_ID_W-1:0]             lp_unit_id,
    input   logic   [REG_ADDR_WIDTH-1:0]        disp_rd_addr,
    input   logic                               disp_rd_wen,
    // RAW 检查（EX 阶段）
    input   logic   [REG_ADDR_WIDTH-1:0]        reg_rs1_raddr_ex,
    input   logic                               ex_rs1_valid,
    input   logic   [REG_ADDR_WIDTH-1:0]        reg_rs2_raddr_ex,
    input   logic                               ex_rs2_valid,
    // WAW 检查（EX 阶段）
    input   logic   [REG_ADDR_WIDTH-1:0]        reg_rd_waddr_ex,
    input   logic                               reg_rd_wen_ex,
    // 长周期单元状态
    input   logic   [NUM_LP_UNITS-1:0]          unit_ready,
    input   logic   [NUM_LP_UNITS-1:0]          unit_wbck_valid,
    input   logic   [NUM_LP_UNITS*DATA_WIDTH-1:0] result_wbck, // 打包：[unit1_res, unit0_res]
    // 控制
    input   logic                               flush,
    // 输出
    output  logic                               oitf_stall,
    output  logic                               retire_valid,
    output  logic   [REG_ADDR_WIDTH-1:0]        retire_rd_addr,
    output  logic   [DATA_WIDTH-1:0]            retire_rd_data,
    output  logic                               retire_rd_wen
);

// ==========================================================================
// 信号定义（条目状态：按字段拆分的并行数组，见文件头说明）
// ==========================================================================
logic   [OITF_DEPTH-1:0]            cur_vld;
logic   [OITF_DEPTH-1:0]            cur_ready;
logic   [OITF_DEPTH-1:0]            cur_rd_wen;
logic   [UNIT_ID_W-1:0]             cur_unit_id  [OITF_DEPTH-1:0];
logic   [REG_ADDR_WIDTH-1:0]        cur_rd_addr  [OITF_DEPTH-1:0];
logic   [DATA_WIDTH-1:0]            cur_result   [OITF_DEPTH-1:0];

logic   [OITF_DEPTH-1:0]            nxt_vld;
logic   [OITF_DEPTH-1:0]            nxt_ready;
logic   [OITF_DEPTH-1:0]            nxt_rd_wen;
logic   [UNIT_ID_W-1:0]             nxt_unit_id  [OITF_DEPTH-1:0];
logic   [REG_ADDR_WIDTH-1:0]        nxt_rd_addr  [OITF_DEPTH-1:0];
logic   [DATA_WIDTH-1:0]            nxt_result   [OITF_DEPTH-1:0];

// FIFO 指针
logic   [ITAG_WIDTH-1:0]    wr_ptr;
(* MAX_FANOUT = 16 *)logic   [ITAG_WIDTH-1:0]    rd_ptr;
logic   [ITAG_WIDTH-1:0]    wr_ptr_nxt;
logic   [ITAG_WIDTH-1:0]    rd_ptr_nxt;
logic   [ITAG_WIDTH:0]      cnt;
logic   [ITAG_WIDTH:0]      cnt_nxt;
logic                       empty, full;

// 派发 & 退休
logic                       disp_fire;
logic                       retire_fire;

// RAW 依赖
logic   [OITF_DEPTH-1:0]    rs1_match;
logic   [OITF_DEPTH-1:0]    rs2_match;
logic                       rs1_hit, rs2_hit;
logic                       raw_hazard;

// WAW 依赖
logic   [OITF_DEPTH-1:0]    waw_match;
logic                       waw_hit;

// 写回匹配：每个 unit 选中一条待更新条目
logic   [OITF_DEPTH-1:0]    wbck_sel  [NUM_LP_UNITS-1:0];

// ==========================================================================
// 组合逻辑
// ==========================================================================
// --- FIFO 空满 ---
assign  empty   = (cnt == '0);
assign  full    = (cnt == OITF_DEPTH);

// --- 派发条件 ---
assign  disp_fire = lp_valid & ~oitf_stall & ~flush;

// --- 退休条件 ---
assign  retire_fire = cur_vld[rd_ptr]
                    & cur_ready[rd_ptr];

// --- RAW 依赖（EX 阶段：当前 EX 指令的 rs 与 OITF 条目的 rd 冲突）---
// 修复：仅当匹配条目"本拍正在退休"（位于 FIFO 头部且 ready）时才解除阻塞。
// 因为前递数据源 lp_retire_wdata 只在头部条目退休那一拍提供其数据。若较年轻
// 的快单元条目（如 MUL）已 ready 但仍在 FIFO 中（头部是更老的慢单元如 DIV，
// 尚未退休），其数据尚无法前递，必须继续停顿，否则会读到寄存器堆中的陈旧值。
// 原实现用 ~oitf_cur[j].ready，会在"结果已算好但未退休"时错误放行 → 数据错误。
generate
    genvar j;
    for (j = 0; j < OITF_DEPTH; j++) begin : gen_raw_match
        assign rs1_match[j] = cur_vld[j]
                             & cur_rd_wen[j]
                             & (cur_rd_addr[j] == reg_rs1_raddr_ex)
                             & ~((j == rd_ptr) & cur_ready[j]);
        assign rs2_match[j] = cur_vld[j]
                             & cur_rd_wen[j]
                             & (cur_rd_addr[j] == reg_rs2_raddr_ex)
                             & ~((j == rd_ptr) & cur_ready[j]);
    end
endgenerate

assign  rs1_hit = |rs1_match;
assign  rs2_hit = |rs2_match;

// 非 longpipe 指令才检查 RAW（longpipe 自身已通过 disp_fire 保证了
// 无冲突才能入队；若 longpipe 自身与 OITF 有 RAW，oitf_stall 已包含
// unit_ready 条件，会被停顿）
assign  raw_hazard = (ex_rs1_valid & rs1_hit) | (ex_rs2_valid & rs2_hit);

// --- WAW 依赖（EX 阶段：当前 EX 指令的 rd 与 OITF 任何有效条目冲突）---
// 同 RAW 修复：仅当匹配条目"本拍正在退休"时才解除阻塞，否则较年轻指令会抢先
// 写回，随后被尚未退休的更老 OITF 条目（双写端口 port2）覆盖，导致最终值错误。
generate
    genvar k;
    for (k = 0; k < OITF_DEPTH; k++) begin : gen_waw_match
        assign waw_match[k] = cur_vld[k]
                             & cur_rd_wen[k]
                             & (cur_rd_addr[k] == reg_rd_waddr_ex)
                             & ~((k == rd_ptr) & cur_ready[k]);
    end
endgenerate

assign  waw_hit = |waw_match;

// --- 写回匹配 ---
// 每个 unit 完成时，从 rd_ptr 顺序扫描，找到该 unit 最老的未就绪条目
// 同一 unit 内指令按 FIFO 顺序完成（流水线固定延迟 / 单发），因此首
// 个匹配即为正确条目
generate
    genvar u;
    for (u = 0; u < NUM_LP_UNITS; u++) begin : gen_wbck_match
        wire [UNIT_ID_W-1:0] u_w = u;
        always_comb begin
            wbck_sel[u] = '0;//每个 unit 有自己的 OITF_DEPTH 位宽的位向量wbck_sel，bit i = 1 表示 entry i 应当接收该 unit 的写回结果。
            if (unit_wbck_valid[u]) begin//这个 unit 刚完成运算,需要匹配
                for (int offset = 0; offset < OITF_DEPTH; offset++) begin//遍历所有 OITF_DEPTH 个条目。注意这里不是按索引 0→1→2→3 的顺序扫，而是从 rd_ptr 开始。
                    // 环形索引用模运算内联
                    if (cur_vld[(rd_ptr + offset) % OITF_DEPTH]
                        && (cur_unit_id[(rd_ptr + offset) % OITF_DEPTH] == u_w)
                        && !cur_ready[(rd_ptr + offset) % OITF_DEPTH]
                        && (wbck_sel[u] == '0)) begin//"首匹配" 条件。已经找到了就停下，后面的不再选。这保证只选最老的那个匹配条目。
                        wbck_sel[u][(rd_ptr + offset) % OITF_DEPTH] = 1'b1;
                    end
                end
            end
        end
    end
endgenerate

// --- 流水线停顿条件 ---
assign  oitf_stall = (lp_valid & (full | (lp_unit_id == 1 && ~unit_ready[1])))//长指令入队时，如果 FIFO 已满或当前长周期单元未就绪，则停顿
                   | raw_hazard // RAW 依赖
                   | (reg_rd_wen_ex & waw_hit);//WAW 依赖

// --- 退休输出（双写端口，OITF 退休走 Port2，无需与 WB 互斥）---
assign  retire_valid    = retire_fire;
assign  retire_rd_addr  = cur_rd_addr[rd_ptr];
assign  retire_rd_data  = cur_result[rd_ptr];
assign  retire_rd_wen   = cur_rd_wen[rd_ptr];

// --- 条目状态更新 ---
always_comb begin
    for (int i = 0; i < OITF_DEPTH; i++) begin
        // 默认保持
        nxt_vld[i]      = cur_vld[i];
        nxt_ready[i]    = cur_ready[i];
        nxt_rd_wen[i]   = cur_rd_wen[i];
        nxt_unit_id[i]  = cur_unit_id[i];
        nxt_rd_addr[i]  = cur_rd_addr[i];
        nxt_result[i]   = cur_result[i];
        if (flush) begin
            nxt_vld[i]   = 1'b0;
            nxt_ready[i] = 1'b0;
        end else begin
            // 派发：写入新条目
            // 注意：不用 '{...} struct assignment pattern——Yosys 不支持
            if (disp_fire && (ITAG_WIDTH'(i) == wr_ptr)) begin
                nxt_vld[i]     = 1'b1;
                nxt_unit_id[i] = lp_unit_id;
                nxt_rd_addr[i] = disp_rd_addr;
                nxt_rd_wen[i]  = disp_rd_wen;
                nxt_ready[i]   = 1'b0;
                nxt_result[i]  = '0;
            end
            // 写回：unit 完成时标记对应条目就绪
            for (int u = 0; u < NUM_LP_UNITS; u++) begin
                if (wbck_sel[u][i]) begin
                    nxt_ready[i]  = 1'b1;
                    nxt_result[i] = result_wbck[u*DATA_WIDTH +: DATA_WIDTH];
                end
            end
            // 退休：清除头部条目
            if (retire_fire && (ITAG_WIDTH'(i) == rd_ptr)) begin
                nxt_vld[i]   = 1'b0;
                nxt_ready[i] = 1'b0;
            end
        end
    end
end

// --- 指针和计数更新 ---
always_comb begin
    wr_ptr_nxt = wr_ptr;
    rd_ptr_nxt = rd_ptr;
    cnt_nxt    = cnt;
    if (flush) begin
        // flush 后 FIFO 为空：rd_ptr 归位到 wr_ptr
        rd_ptr_nxt = wr_ptr;
        cnt_nxt    = '0;
    end else begin
        if (disp_fire) begin
            wr_ptr_nxt = (wr_ptr == OITF_DEPTH - 1) ? 'h0 : wr_ptr + 'h1;
            cnt_nxt    = cnt + 'h1;
        end
        if (retire_fire) begin
            rd_ptr_nxt = (rd_ptr == OITF_DEPTH - 1) ? 'h0 : rd_ptr + 'h1;
            cnt_nxt    = cnt_nxt - 'h1;
        end
    end
end

// ==========================================================================
// 时序逻辑
// ==========================================================================
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        for (int i = 0; i < OITF_DEPTH; i++) begin
            cur_vld[i]     <= #1 '0;
            cur_ready[i]   <= #1 '0;
            cur_rd_wen[i]  <= #1 '0;
            cur_unit_id[i] <= #1 '0;
            cur_rd_addr[i] <= #1 '0;
            cur_result[i]  <= #1 '0;
        end
        wr_ptr <= #1 '0;
        rd_ptr <= #1 '0;
        cnt    <= #1 '0;
    end else begin
        for (int i = 0; i < OITF_DEPTH; i++) begin
            cur_vld[i]     <= #1 nxt_vld[i];
            cur_ready[i]   <= #1 nxt_ready[i];
            cur_rd_wen[i]  <= #1 nxt_rd_wen[i];
            cur_unit_id[i] <= #1 nxt_unit_id[i];
            cur_rd_addr[i] <= #1 nxt_rd_addr[i];
            cur_result[i]  <= #1 nxt_result[i];
        end
        wr_ptr <= #1 wr_ptr_nxt;
        rd_ptr <= #1 rd_ptr_nxt;
        cnt    <= #1 cnt_nxt;
    end
end

`ifndef SYNTHESIS
// ===== SVA：FIFO 一致性（仿真 + 形式共享）=====
// Yosys SVA 子集写法：时钟取自外层 always（模块级 @(posedge) 不支持）、
// disable iff 改为 if 守卫、蕴含 |=> 改写为 $past 守卫（ModelSim 同样接受）
always @(posedge clk) begin
    if (rst_n) begin
        // 计数永不超深度（入队/退休/flush 三方更新无双重计数）
        a_cnt_range: assert property (cnt <= OITF_DEPTH);
        // 异常 flush 清空 FIFO：次拍 cnt=0 且读指针归位写指针
        if ($past(flush)) begin
            a_flush_empty: assert property ((cnt == '0) && (rd_ptr == wr_ptr));
        end
    end
end
`endif

`ifdef FORMAL
// ===== 形式验证属性（SymbiYosys BMC/prove）=====
// FIFO 序不变式（核心）：环形偏移 rel < cnt ⟺ 条目在队
genvar gf;
for (gf = 0; gf < OITF_DEPTH; gf++) begin : gen_fml_order
    wire [ITAG_WIDTH-1:0] gf_w      = gf;
    wire [ITAG_WIDTH-1:0] ring_rel_f = (gf_w - rd_ptr);
    // 与全宽 cnt 比较（cnt==OITF_DEPTH 满时低 2 位为 00，截断比较会误判为空）
    wire                  in_win_f   = ({1'b0, ring_rel_f} < cnt);
    always @(posedge clk) begin
        if (rst_n) begin
            // 无标签：generate 展开时 Yosys 不接受同名 assert cell，自动命名即可
            assert property (cur_vld[gf] == in_win_f);
        end
    end
end
// 停顿一致性：oitf_stall 的独立重构（wire 声明于模块级，always 内引用）
wire fml_exp_raw   = ((ex_rs1_valid & rs1_hit) | (ex_rs2_valid & rs2_hit));
wire fml_exp_stall = (lp_valid & (full | ((lp_unit_id == 1'b1) && !unit_ready[1])))
                   | fml_exp_raw
                   | (reg_rd_wen_ex & waw_hit);
// 指针范围 / 退休合法性 / 停顿一致性：同一 always 内集中书写
always @(posedge clk) begin
    if (rst_n) begin
        a_fml_wr_range: assert property (wr_ptr < OITF_DEPTH);
        a_fml_rd_range: assert property (rd_ptr < OITF_DEPTH);
        // 退休合法性：retire_valid 仅当头部条目 vld 且 ready
        a_fml_retire_def: assert property
            (retire_valid == (cur_vld[rd_ptr] && cur_ready[rd_ptr]));
        // 空 FIFO 无退休
        if (cnt == '0) begin
            a_fml_no_retire_empty: assert property (!retire_valid);
        end
        // 退休输出与头部条目一致
        if (retire_valid) begin
            a_fml_retire_out: assert property
                ((retire_rd_addr == cur_rd_addr[rd_ptr]) &&
                 (retire_rd_data == cur_result[rd_ptr]));
        end
        // 停顿一致性
        a_fml_stall_match: assert property (oitf_stall == fml_exp_stall);
        // cover：稀有路径
        c_fml_full:  cover property (full);
        c_fml_rf_fl: cover property (retire_fire && flush);
        c_fml_dp_rt: cover property (disp_fire && retire_fire);
    end
end
`endif

`ifdef ASSERT_MODULE
// ===== SVA L2：OITF 深化——计数守恒与退休合法性（formal B/F 组的仿真采样版）=====
always @(posedge clk) begin
    if (rst_n) begin
        // cnt 与有效条目数逐拍一致
        a_l2_oitf_cnt: assert property (cnt == $countones(cur_vld));
        // 空队列恒无退休
        if (cnt == 'd0) a_l2_oitf_empty_noret: assert property (!retire_fire);
        // 退休必来自头部且该条目就绪
        if (retire_fire) a_l2_oitf_head: assert property (cur_vld[rd_ptr] && cur_ready[rd_ptr]);
    end
end
`endif

endmodule
