// ==========================================================================
// OITF (Outstanding Instruction Tracking FIFO)  —— 未完成指令跟踪 FIFO
// ==========================================================================
//
// 【背景】
//   MUL/DIV/REM 等乘除法指令需要 4~33 个时钟周期才能算出结果。
//   如果流水线一直停顿等结果，其后无依赖的 ALU 指令白等几十拍。
//
// 【OITF 的作用】
//   乘除法器独立运行（不阻塞流水线），OITF 作为"登记簿"跟踪那些
//   "已发射但还没算完"的长周期指令。后续 ALU 指令只要不依赖其结果，
//   就可以照常执行。乘除法器算完后，结果写回 OITF 对应条目，再按
//   FIFO 顺序退休写回寄存器堆。
//
// 【设计参考】
//   E203 (Hummingbirdv2) e203_exu_oitf.v
//
// 【BD32 并发支持】
//   - 乘法器和除法器是独立硬件，可同时运行
//   - OITF 条目记录 op_type（MUL/DIV），分别跟踪各自的 cur_itag
//   - 派发条件：MUL 需 mul_ready，DIV 需 div_ready，互不阻塞
// ==========================================================================
`include "./../SoC_Config.sv"

module OITF #(
    parameter OITF_DEPTH    = 4,
    parameter DATA_WIDTH    = `DATA_WIDTH,
    parameter REG_ADDR_WIDTH= `REG_ADDR_WIDTH,
    parameter ITAG_WIDTH    = $clog2(OITF_DEPTH)
)(
    input   logic                               clk,
    input   logic                               rst_n,

    // ======== EX 阶段长周期指令信息 ========
    input   logic                               longpipe_valid,      // EX 阶段确认：当前是长周期指令
    input   logic                               longpipe_longpipe_is_div,     // 1=DIV  0=MUL
    input   logic   [REG_ADDR_WIDTH-1:0]        disp_rd_addr,
    input   logic                               disp_rd_wen,
    // ======== ID 阶段 RAW/WAW 检查 ========
    input   logic                               check_is_muldiv,     // ID 指令是否长周期（MULDIV），非长周期才检查 RAW/WAW
    input   logic   [REG_ADDR_WIDTH-1:0]        check_rs1_addr,
    input   logic                               check_rs1_valid,
    input   logic   [REG_ADDR_WIDTH-1:0]        check_rs2_addr,
    input   logic                               check_rs2_valid,

    // ======== 乘除法器状态（mul/div 独立）========
    input   logic                               mul_ready,           // 乘法器空闲
    input   logic                               div_ready,           // 除法器空闲
    input   logic                               mul_valid,           // 乘法结果有效
    input   logic                               div_valid,           // 除法结果有效
    input   logic   [DATA_WIDTH-1:0]            result_wbck,         // 结果数据（mul_valid 或 div_valid 时有效）

    // ======== 输出 ========
    output  logic                               oitf_stall,
    output  logic                               retire_valid,
    output  logic   [REG_ADDR_WIDTH-1:0]        retire_rd_addr,
    output  logic   [DATA_WIDTH-1:0]            retire_rd_data,
    output  logic                               retire_rd_wen,
    input   logic                               wb_idle,
    input   logic                               flush
);


// ==========================================================================
// 1. OITF 条目结构
// ==========================================================================
// 每个 OITF 条目记录一条已发射但还没退休的长周期指令的全部信息。
// 条目在 dispatch（派发）时写入，在乘除法器写回时更新结果，在退休时清除。
typedef struct packed {
    logic                           vld;       // 条目有效标记：1=该条目正在跟踪一条长指令
    logic   [REG_ADDR_WIDTH-1:0]    rd_addr;   // 目的寄存器地址 rd（结果写回的寄存器编号）
    logic                           rd_wen;    // 是否写寄存器（有些指令如 csr 不写 rd）
    logic                           ready;     // 结果已就绪标记：乘除法器算完后置 1，等待 FIFO 退休
    logic   [DATA_WIDTH-1:0]        result;    // 乘除法器算出的结果（ready=1 时有效）
} oitf_entry_t;

oitf_entry_t    oitf_cur    [OITF_DEPTH-1:0];   // 时序逻辑：当前状态（寄存器输出）
oitf_entry_t    oitf_nxt    [OITF_DEPTH-1:0];   // 组合逻辑：下一拍状态


// ==========================================================================
// 2. FIFO 读写指针 & 空满判断
// ==========================================================================
// OITF 是一个环形 FIFO：
//   wr_ptr（写指针）：指向下一个要写入的空条目
//   rd_ptr（读指针）：指向下一个要退休的条目（FIFO 顶部）
//   当 wr_ptr == rd_ptr 且 cnt == 0 时 FIFO 为空
//   当 wr_ptr == rd_ptr 且 cnt == DEPTH 时 FIFO 为满
logic   [ITAG_WIDTH-1:0]            wr_ptr;       // 写指针：下一个可写入的位置
logic   [ITAG_WIDTH-1:0]            rd_ptr;       // 读指针：下一个可退休的位置
logic   [ITAG_WIDTH-1:0]            wr_ptr_nxt;   // 写指针下一拍
logic   [ITAG_WIDTH-1:0]            rd_ptr_nxt;   // 读指针下一拍
logic   [ITAG_WIDTH:0]              cnt;           // FIFO 当前占用条目数
logic   [ITAG_WIDTH:0]              cnt_nxt;       // 下一拍的占用数

// 空满标记（通知外部/OITF 内部逻辑使用）
logic   empty;
logic   full;
assign  empty   = (cnt == '0);
assign  full    = (cnt == OITF_DEPTH);


// ==========================================================================
// 3. 派发逻辑：何时将一条 mul/div 指令登记到 OITF
// ==========================================================================
// OITF 根据 Decoder 给出的 inst_type 判断当前 ID 指令是否为长周期指令。
// inst_type == 6 表示 MUL/DIV/REM。
//
// 派发条件：MUL 和 DIV 分别检查各自单元的空闲状态，互不阻塞
logic   disp_fire;
assign  disp_fire = longpipe_valid & ~oitf_stall & (longpipe_longpipe_is_div ? div_ready : mul_ready);

// ==========================================================================
// 4. cur_itag_mul / cur_itag_div — 分别跟踪 Mul 和 Div 单元中的指令
// ==========================================================================
// dispatch 时锁存 wr_ptr，结果回来时用对应的 cur_itag 匹配 OITF 条目
logic   [ITAG_WIDTH-1:0]    cur_itag_mul;
logic                       cur_itag_mul_vld;
logic   [ITAG_WIDTH-1:0]    cur_itag_div;
logic                       cur_itag_div_vld;

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        cur_itag_mul_vld <= #1 1'b0;
        cur_itag_div_vld <= #1 1'b0;
    end else begin
        // mul 派发 → 置 mul 有效
        if (disp_fire & ~longpipe_is_div)
            cur_itag_mul_vld <= #1 1'b1;
        else if (retire_fire & cur_itag_mul_vld & (ITAG_WIDTH'(cur_itag_mul) == rd_ptr))
            cur_itag_mul_vld <= #1 1'b0;
        // div 派发 → 置 div 有效
        if (disp_fire & longpipe_is_div)
            cur_itag_div_vld <= #1 1'b1;
        else if (retire_fire & cur_itag_div_vld & (ITAG_WIDTH'(cur_itag_div) == rd_ptr))
            cur_itag_div_vld <= #1 1'b0;
    end
end

always_ff @(posedge clk) begin
    if (disp_fire & ~longpipe_is_div)
        cur_itag_mul <= #1 wr_ptr;
    if (disp_fire & longpipe_is_div)
        cur_itag_div <= #1 wr_ptr;
end

always_ff @(posedge clk) begin
    if (disp_fire)
        cur_itag <= #1 wr_ptr;                        // 锁存派发时的写指针
end


// ==========================================================================
// 5. RAW 依赖检查（Read-After-Write Hazard）
// ==========================================================================
// 当一条非长周期指令（ALU/Load/Store等）进入 ID 阶段时，需要检查：
// 它的源寄存器（rs1/rs2）是否与 OITF 中某条"正在等结果"的指令的 rd 相同？
//
// 对比逻辑逐条遍历 OITF 所有条目（j = 0..OITF_DEPTH-1）：
//   rs1_match[j] = 条目 j 有效 & 写寄存器 & rd==当前rs1 & 还没就绪
// 只要任一条目命中，就存在 RAW 依赖 → 必须停顿等结果。
//
// 注意：ready 已为 1 的条目不算依赖——因为结果已就绪，即将退休写回。
logic   [OITF_DEPTH-1:0] rs1_match ;   // rs1 与每个 OITF 条目的比较结果
logic   [OITF_DEPTH-1:0] rs2_match ;   // rs2 与每个 OITF 条目的比较结果
logic   rs1_hit;                        // rs1 是否有 RAW 冲突
logic   rs2_hit;                        // rs2 是否有 RAW 冲突

generate
    genvar j;
    for (j = 0; j < OITF_DEPTH; j++) begin : gen_raw_match
        // rs1 冲突条件 4 个：条目有效、会写寄存器、rd 地址匹配、还没就绪
        assign rs1_match[j] = oitf_cur[j].vld
                           & oitf_cur[j].rd_wen
                           & (oitf_cur[j].rd_addr == check_rs1_addr)
                           & ~oitf_cur[j].ready;
        // rs2 同理
        assign rs2_match[j] = oitf_cur[j].vld
                           & oitf_cur[j].rd_wen
                           & (oitf_cur[j].rd_addr == check_rs2_addr)
                           & ~oitf_cur[j].ready;
    end
endgenerate

assign  rs1_hit = |rs1_match;          // 任一条目匹配 → 依赖命中
assign  rs2_hit = |rs2_match;

// RAW 危险仅对非长周期指令检查（长周期指令自己走 OITF track，不等结果）
logic   raw_hazard;
assign  raw_hazard = (~check_is_muldiv) & (
       (check_rs1_valid & rs1_hit)
     | (check_rs2_valid & rs2_hit)
);


// ==========================================================================
// 6. WAW 依赖检查（Write-After-Write Hazard）
// ==========================================================================
// 当一条非长周期指令写 rd，但 OITF 中有一条未完成的长周期指令也写同一个 rd。
// 如果不停顿，ALU 结果会先写进寄存器堆，稍后 OITF 退休时又覆盖它 → 错误！
//
// 对比逻辑逐条遍历：
//   waw_match[j] = 条目 j 有效 & 写寄存器 & rd==当前rd & 还没就绪
// 任一条目命中 → 存在 WAW 依赖 → 必须停顿。
logic   [OITF_DEPTH-1:0] waw_match;    // rd 与每个 OITF 条目的比较结果
logic   waw_hit;                         // 是否有 WAW 冲突

generate
    genvar k;
    for (k = 0; k < OITF_DEPTH; k++) begin : gen_waw_match
        assign waw_match[k] = oitf_cur[k].vld
                           & oitf_cur[k].rd_wen
                           & (oitf_cur[k].rd_addr == disp_rd_addr)
                           & ~oitf_cur[k].ready;
    end
endgenerate
assign  waw_hit = |waw_match;


// ==========================================================================
// 7. oitf_stall：流水线停顿条件
// ==========================================================================
// 停顿分两种情况：
//   (a) MUL → mul_ready=0 或 OITF 满
//       DIV → div_ready=0 或 OITF 满
//   (b) 非长指令 → RAW/WAW 依赖
logic   unit_busy;
assign  unit_busy = longpipe_is_div ? ~div_ready : ~mul_ready;
assign  oitf_stall = (longpipe_valid & (unit_busy | full))
                   | (~check_is_muldiv & (raw_hazard | waw_hit));


// ==========================================================================
// 8. 退休逻辑：OITF FIFO 顶部就绪 → 写回寄存器堆
// ==========================================================================
// OITF 是 FIFO（先进先出），只有顶部（rd_ptr 指向的条目）就绪时才能退休。
// 这保证了长周期指令按原始程序顺序写回，不会乱序。
//
// 退休条件（retire_valid）：
//   顶部条目有效 & 顶部条目结果已就绪 & WB 写端口空闲
//
// 退休时：读指针对应的 rd_addr/result/rd_wen 输出给寄存器堆写端口。
wire    retire_fire = retire_valid;      // 退休触发（用于指针更新）

assign  retire_valid    = oitf_cur[rd_ptr].vld
                       & oitf_cur[rd_ptr].ready    // FIFO 顶部就绪
                       & wb_idle;                   // WB 阶段有空闲写端口

assign  retire_rd_addr  = oitf_cur[rd_ptr].rd_addr;
assign  retire_rd_data  = oitf_cur[rd_ptr].result;
assign  retire_rd_wen   = oitf_cur[rd_ptr].rd_wen;


// ==========================================================================
// 9. 每个 OITF 条目的状态更新（组合逻辑 oitf_nxt）
// ==========================================================================
// 每个时钟周期，每个条目可能发生以下事件之一（或同时发生多个）：
//   0. flush → 全部清除（优先级最高）
//   1. dispatch（派发）→ 写指针位置填入新指令信息
//   2. writeback（乘除法器写回）→ cur_itag 位置的条目 ready 置 1
//   3. retire（退休）→ 读指针位置条目清空
always_comb begin
    for (int i = 0; i < OITF_DEPTH; i++) begin
        oitf_nxt[i] = oitf_cur[i];                // 默认保持

        // 0. 冲刷：分支误预测/异常时清除所有 OITF 条目
        //    注意：乘除法器一旦启动就无法中断，冲刷后它仍会产生一个结果。
        //    此时 cur_itag 对应的 OITF 条目已被清空，结果被忽略，正确。
        if (flush) begin
            oitf_nxt[i].vld   = 1'b0;
            oitf_nxt[i].ready = 1'b0;
        end else begin

        // 1. 新派发：在写指针位置登记一条长周期指令
        if (disp_fire && (ITAG_WIDTH'(i) == wr_ptr)) begin
            oitf_nxt[i].vld     = 1'b1;          // 标记条目有效
            oitf_nxt[i].rd_addr = disp_rd_addr;  // 记录目的寄存器
            oitf_nxt[i].rd_wen  = disp_rd_wen;   // 记录是否写回
            oitf_nxt[i].ready   = 1'b0;
        end

        // 2. 乘法器写回 → cur_itag_mul 条目
        if (mul_valid && cur_itag_mul_vld && (ITAG_WIDTH'(i) == cur_itag_mul)) begin
            oitf_nxt[i].ready  = 1'b1;
            oitf_nxt[i].result = result_wbck;
        end
        // 2b. 除法器写回 → cur_itag_div 条目
        if (div_valid && cur_itag_div_vld && (ITAG_WIDTH'(i) == cur_itag_div)) begin
            oitf_nxt[i].ready  = 1'b1;
            oitf_nxt[i].result = result_wbck;
        end

        // 3. FIFO 退休：弹出顶部条目
        if (retire_fire && (ITAG_WIDTH'(i) == rd_ptr)) begin
            oitf_nxt[i].vld   = 1'b0;            // 清除有效标记
            oitf_nxt[i].ready = 1'b0;            // 清除就绪标记
        end
        end
    end
end


// ==========================================================================
// 10. FIFO 指针和计数更新
// ==========================================================================
//   dispatch 时：wr_ptr + 1
//   retire  时：rd_ptr + 1
//   同时 dispatch + retire 时：wr_ptr 和 rd_ptr 都前进，cnt 不变
always_comb begin
    wr_ptr_nxt = wr_ptr;
    rd_ptr_nxt = rd_ptr;
    cnt_nxt    = cnt;

    if (disp_fire) begin
        wr_ptr_nxt = (wr_ptr == OITF_DEPTH - 1) ? 'h0 : wr_ptr + 'h1;     // 写指针前进
        cnt_nxt    = cnt + 'h1;        // 计数 +1
    end

    if (retire_fire) begin
        rd_ptr_nxt = (rd_ptr == OITF_DEPTH - 1) ? 'h0 : rd_ptr + 'h1;     // 读指针前进
        cnt_nxt    = cnt_nxt - 'h1;    // 计数 -1（注意用 cnt_nxt 而非 cnt，兼容同时 dispatch）
    end
end


// ==========================================================================
// 11. 时序逻辑（寄存器）
// ==========================================================================
// 所有 OITF 状态（条目内容 + 指针 + 计数）统一打一拍
always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        for (int i = 0; i < OITF_DEPTH; i++) begin
            oitf_cur[i] <= #1 '0;                          // 复位清空
        end
        wr_ptr <= #1 '0;
        rd_ptr <= #1 '0;
        cnt    <= #1 '0;
    end else begin
        for (int i = 0; i < OITF_DEPTH; i++) begin
            oitf_cur[i] <= #1 oitf_nxt[i];                 // 条目内容更新
        end
        wr_ptr <= #1 wr_ptr_nxt;                            // 写指针前进
        rd_ptr <= #1 rd_ptr_nxt;                            // 读指针前进
        cnt    <= #1 cnt_nxt;                               // 计数更新
    end
end

endmodule
