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
// ==========================================================================
`include "./../SoC_Config.sv"
timeunit 1ns;
timeprecision 1ps;
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
// 类型定义
// ==========================================================================
typedef struct packed {
    logic                           vld;
    logic   [UNIT_ID_W-1:0]         unit_id;        // 所属长周期单元
    logic   [REG_ADDR_WIDTH-1:0]    rd_addr;
    logic                           rd_wen;
    logic                           ready;          // 结果已就绪
    logic   [DATA_WIDTH-1:0]        result;
} oitf_entry_t;

// ==========================================================================
// 信号定义
// ==========================================================================
// 条目数组
oitf_entry_t    oitf_cur    [OITF_DEPTH-1:0];
oitf_entry_t    oitf_nxt    [OITF_DEPTH-1:0];

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
assign  retire_fire = oitf_cur[rd_ptr].vld
                    & oitf_cur[rd_ptr].ready;

// --- RAW 依赖（EX 阶段：当前 EX 指令的 rs 与 OITF 未就绪条目的 rd 冲突）---
generate
    genvar j;
    for (j = 0; j < OITF_DEPTH; j++) begin : gen_raw_match
        assign rs1_match[j] = oitf_cur[j].vld
                             & oitf_cur[j].rd_wen
                             & (oitf_cur[j].rd_addr == reg_rs1_raddr_ex)
                             & ~oitf_cur[j].ready;
        assign rs2_match[j] = oitf_cur[j].vld
                             & oitf_cur[j].rd_wen
                             & (oitf_cur[j].rd_addr == reg_rs2_raddr_ex)
                             & ~oitf_cur[j].ready;
    end
endgenerate

assign  rs1_hit = |rs1_match;
assign  rs2_hit = |rs2_match;

// 非 longpipe 指令才检查 RAW（longpipe 自身已通过 disp_fire 保证了
// 无冲突才能入队；若 longpipe 自身与 OITF 有 RAW，oitf_stall 已包含
// unit_ready 条件，会被停顿）
assign  raw_hazard = (~lp_valid) & (
                         (ex_rs1_valid & rs1_hit)
                       | (ex_rs2_valid & rs2_hit)
                     );

// --- WAW 依赖（EX 阶段：当前 EX 指令的 rd 与 OITF 任何有效条目冲突）---
generate
    genvar k;
    for (k = 0; k < OITF_DEPTH; k++) begin : gen_waw_match
        assign waw_match[k] = oitf_cur[k].vld
                             & oitf_cur[k].rd_wen
                             & (oitf_cur[k].rd_addr == reg_rd_waddr_ex);
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
        always_comb begin
            wbck_sel[u] = '0;//每个 unit 有自己的 OITF_DEPTH 位宽的位向量wbck_sel，bit i = 1 表示 entry i 应当接收该 unit 的写回结果。
            if (unit_wbck_valid[u]) begin//这个 unit 刚完成运算,需要匹配
                for (int offset = 0; offset < OITF_DEPTH; offset++) begin//遍历所有 OITF_DEPTH 个条目。注意这里不是按索引 0→1→2→3 的顺序扫，而是从 rd_ptr 开始。
                    automatic int idx;
                    idx = (int'(rd_ptr) + offset >= OITF_DEPTH) ? (int'(rd_ptr) + offset - OITF_DEPTH) : int'(rd_ptr) + offset;
                    if (oitf_cur[idx].vld
                        && (oitf_cur[idx].unit_id == u[UNIT_ID_W-1:0])
                        && !oitf_cur[idx].ready
                        && (wbck_sel[u] == '0)) begin//"首匹配" 条件。已经找到了就停下，后面的不再选。这保证只选最老的那个匹配条目。
                        wbck_sel[u][idx] = 1'b1;
                    end
                end
            end
        end
    end
endgenerate

// --- 流水线停顿条件 ---
assign  oitf_stall = (lp_valid & (full | (lp_unit_id == 1 && ~unit_ready)))//长指令入队时，如果 FIFO 已满或当前长周期单元未就绪，则停顿
                   | raw_hazard // RAW 依赖
                   | (reg_rd_wen_ex & waw_hit);//WAW 依赖

// --- 退休输出（双写端口，OITF 退休走 Port2，无需与 WB 互斥）---
assign  retire_valid    = retire_fire;
assign  retire_rd_addr  = oitf_cur[rd_ptr].rd_addr;
assign  retire_rd_data  = oitf_cur[rd_ptr].result;
assign  retire_rd_wen   = oitf_cur[rd_ptr].rd_wen;

// --- 条目状态更新 ---
always_comb begin
    for (int i = 0; i < OITF_DEPTH; i++) begin
        oitf_nxt[i] = oitf_cur[i];
        if (flush) begin
            oitf_nxt[i].vld   = 1'b0;
            oitf_nxt[i].ready = 1'b0;
        end else begin
            // 派发：写入新条目
            if (disp_fire && (ITAG_WIDTH'(i) == wr_ptr)) begin
                oitf_nxt[i] = '{
                    vld:     1'b1,
                    unit_id: lp_unit_id,
                    rd_addr: disp_rd_addr,
                    rd_wen:  disp_rd_wen,
                    ready:   1'b0,
                    result:  '0
                };
            end
            // 写回：unit 完成时标记对应条目就绪
            for (int u = 0; u < NUM_LP_UNITS; u++) begin
                if (wbck_sel[u][i]) begin
                    oitf_nxt[i].ready  = 1'b1;
                    oitf_nxt[i].result = result_wbck[u*DATA_WIDTH +: DATA_WIDTH];
                end
            end
            // 退休：清除头部条目
            if (retire_fire && (ITAG_WIDTH'(i) == rd_ptr)) begin
                oitf_nxt[i].vld   = 1'b0;
                oitf_nxt[i].ready = 1'b0;
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
        for (int i = 0; i < OITF_DEPTH; i++)
            oitf_cur[i] <= #1 '0;
        wr_ptr <= #1 '0;
        rd_ptr <= #1 '0;
        cnt    <= #1 '0;
    end else begin
        for (int i = 0; i < OITF_DEPTH; i++)
            oitf_cur[i] <= #1 oitf_nxt[i];
        wr_ptr <= #1 wr_ptr_nxt;
        rd_ptr <= #1 rd_ptr_nxt;
        cnt    <= #1 cnt_nxt;
    end
end

endmodule
