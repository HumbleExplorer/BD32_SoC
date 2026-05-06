`include "../../SoC_Config.sv"
`timescale 1ns / 1ps
// =============================================================================
// PLIC (Platform-Level Interrupt Controller)
// RISC-V PLIC Spec v1.10 兼容
//
// 子模块:
//   - plic_gateway  : 单源 Gateway (电平/边沿触发, claim/complete 状态机)
//   - plic_target   : 单目标 Claim/Complete FSM (IDLE/CLAIMED)
//   - CompareTree   : 参数化二叉比较树 (全局唯一, 选出最高优先级源)
//
// 参数化:
//   NUM_SOURCES    : 中断源数量 (含 source 0, 实际可用 NUM_SOURCES-1)
//   MAX_PRIORITY : 最大优先级值 (0 为禁用, 有效范围 1..MAX_PRIORITY)
//   NUM_TARGETS    : 目标(hart)数量
//   SYNC_STAGES    : IRQ 输入同步级数 (0=旁路, >=1 打拍)
//
// 地址映射 (PADDR[15:2] 为 word 地址, 低 2 位 byte-offset 忽略):
//   Priority  : 0x0000 ~ 0x0FFC  (每源 4Byte, source 0 = 0)
//   Pending   : 0x1000 ~ 0x107C  (只读, 每 32 源一个 Word)
//   Target    : 0x2000 ~         (每目标 0x100 对齐)
//     +0x00  enable    (128Byte)
//     +0x80  threshold
//     +0x84  claim/complete
// =============================================================================
module PLIC #(
    parameter ADDR_WIDTH     = `ADDR_WIDTH,
    parameter DATA_WIDTH     = `DATA_WIDTH,
    parameter ALIGN_BYTES    = `ALIGN_BYTES,
    parameter NUM_SOURCES    = 16,     // 含 source 0 (保留)
    parameter MAX_PRIORITY   = 7,      // 最大优先级 (0 = 禁用)
    parameter NUM_TARGETS    = 1,
    parameter SYNC_STAGES    = 2,      // IRQ 同步级数
    localparam PRIO_WIDTH    = $clog2(MAX_PRIORITY + 1),
    localparam SRC_ID_WIDTH  = $clog2(NUM_SOURCES + 1),
    localparam TGT_IDX_WIDTH = (NUM_TARGETS > 1) ? $clog2(NUM_TARGETS) : 1,
    // CompareTree 要求 DATA_NUM 为 2 的幂, 向上取整
    localparam CT_NUM        = 1 << $clog2(NUM_SOURCES),
    localparam CT_IDX_W      = $clog2(CT_NUM)
)(
    // APB 接口
    input   logic                       PCLK,
    input   logic                       PRESETn,
    input   logic   [ADDR_WIDTH-1:0]    PADDR,
    input   logic                       PSEL,
    input   logic                       PENABLE,
    input   logic                       PWRITE,
    input   logic   [ALIGN_BYTES-1:0]   PSTRB,
    input   logic   [DATA_WIDTH-1:0]    PWDATA,
    output  logic   [DATA_WIDTH-1:0]    PRDATA,
    output  logic                       PREADY,
    output  logic                       PSLVERR,

    // 中断请求输入 (每源一个, source 0 保留接 0)
    input   logic   [NUM_SOURCES-1:0]   irq_i,

    // 目标输出 (每 hart 一个)
    output  logic   [NUM_TARGETS-1:0]   irq_o
);

    // ========================================================================
    // 区域边界 (word 对齐, byte_addr / 4)
    // 直接用 PADDR[15:2] 做 word 地址, 与 CLINT 风格一致
    //   Priority  : 0x0000 ~ 0x0FFF  → PADDR[15:14] == 0
    //   Pending   : 0x1000 ~ 0x1FFF  → PADDR[15:14] == 1
    //   Target    : 0x2000 ~         → PADDR[15:14] >= 2
    // ========================================================================
    localparam PRIORITY_ADDR = 16'h0000;
    localparam PENDING_ADDR  = 16'h1000;
    localparam TARGET_ADDR   = 16'h2000;
    // Target 块内偏移 (word 对齐)
    localparam TGT_THRESH_OFF = 8'h80;
    localparam TGT_CLAIM_OFF  = 8'h84;

    // ========================================================================
    // 内部信号 - 地址译码
    // src_idx: Priority 区的源 ID (直接对应某个中断源)
    // word_idx: Pending/Enable 区的 word 索引 (每 word 对应 32 个源)
    // tgt_idx: Target 区的目标索引
    // ========================================================================
    logic                       is_prio;
    logic                       is_pending;
    logic                       is_target_enable;
    logic                       is_target_threshold;
    logic                       is_target_claim;
    logic   [SRC_ID_WIDTH-1:0]  src_idx;     // Priority: 源 ID
    logic   [4:0]               word_idx;    // Pending/Enable: word 索引 (每 word 32 源)
    logic   [TGT_IDX_WIDTH-1:0] tgt_idx;

    // ========================================================================
    // 内部信号 - 寄存器
    // ========================================================================
    (* RAM_STYLE="distributed"*)logic   [PRIO_WIDTH-1:0]    prio_regs   [NUM_SOURCES];    // 每源优先级
    logic   [NUM_SOURCES-1:0]   pending_bits;                  // 来自 gateway
    (* RAM_STYLE="distributed"*)logic   [NUM_SOURCES-1:0]   enable_bits [NUM_TARGETS];    // 每目标使能
    logic   [PRIO_WIDTH-1:0]    threshold_q [NUM_TARGETS];    // 每目标阈值

    // ========================================================================
    // 内部信号 - 同步与 Gateway
    // ========================================================================
    logic   [NUM_SOURCES-1:0]   irq_synced;
    logic   [NUM_SOURCES-1:0]   gateway_claim;
    logic   [NUM_SOURCES-1:0]   gateway_complete;

    // ========================================================================
    // 内部信号 - 每目标独立仲裁
    // ========================================================================
    logic   [NUM_TARGETS-1:0][PRIO_WIDTH*CT_NUM-1:0] ct_input_data;
    // CompareTree 输出打一拍（切断 16 级组合逻辑到 PRDATA 的长路径）
    logic [PRIO_WIDTH-1:0] ct_max_prio_comb [NUM_TARGETS];
    logic [CT_IDX_W-1:0]   ct_max_idx_comb  [NUM_TARGETS];
    logic [PRIO_WIDTH-1:0] ct_max_prio_r [NUM_TARGETS];
    logic [CT_IDX_W-1:0]   ct_max_idx_r  [NUM_TARGETS];
    logic   [NUM_TARGETS-1:0][SRC_ID_WIDTH-1:0]      winner_idx;
    logic   [NUM_TARGETS-1:0][PRIO_WIDTH-1:0]        winner_prio;
    logic   [NUM_TARGETS-1:0]                         irq_valid;

    // ========================================================================
    // 内部信号 - Target
    // ========================================================================
    logic   [NUM_TARGETS-1:0]                   target_claim_read;
    logic   [NUM_TARGETS-1:0]                   target_complete_write;
    logic   [NUM_TARGETS-1:0][SRC_ID_WIDTH-1:0] target_complete_id;
    logic   [NUM_TARGETS-1:0][SRC_ID_WIDTH-1:0] target_claimed_id;
    logic   [NUM_TARGETS-1:0]                   target_eip;

    logic   [NUM_TARGETS-1:0][NUM_SOURCES-1:0]  target_claim_vec;
    logic   [NUM_TARGETS-1:0][NUM_SOURCES-1:0]  target_complete_vec;

    // ========================================================================
    // APB 接口辅助
    // ========================================================================
    logic wr_en, rd_en;
    assign wr_en      = PSEL & PENABLE & PWRITE;
    assign rd_en      = PSEL & PENABLE & ~PWRITE;
    assign PREADY     = 1'b1;   // PLIC 单周期响应
    assign PSLVERR    = 1'b0;   // 无错误响应

    always_comb begin
        is_prio             = 1'b0;
        is_pending          = 1'b0;
        is_target_enable    = 1'b0;
        is_target_threshold = 1'b0;
        is_target_claim     = 1'b0;
        src_idx             = 'h0;
        word_idx            = 'h0;
        tgt_idx             = 'h0;
        case (PADDR[15:12])
            PRIORITY_ADDR[15:12]: begin
                // Priority: 0x0000 ~ 0x0FFC, 每源 4B
                is_prio  = 1'b1;
                src_idx  = PADDR[11:2];
            end
            PENDING_ADDR[15:12]: begin
                // Pending: 0x1000 ~ 0x1FFC (只读), 每 32 源一个 word
                is_pending = 1'b1;
                word_idx   = PADDR[6:2];
            end
            TARGET_ADDR[15:12]: begin
            // Target: 0x2000 ~ ...
            // 每目标 0x100 = 256B, word 粒度 = 0x40 words
                tgt_idx = PADDR[11:8];     // 目标索引

                if (PADDR[7:2] < TGT_THRESH_OFF[7:2]) begin
                    // Enable: 块内 +0x00 ~ +0x7C (128B = 32 words)
                    is_target_enable = 1'b1;
                    word_idx = PADDR[6:2];  // 每 32 源一个 word

                end else if (PADDR[7:2] == TGT_THRESH_OFF[7:2]) begin
                    // Threshold: 块内 +0x80
                    is_target_threshold = 1'b1;

                end else if (PADDR[7:2] == TGT_CLAIM_OFF[7:2]) begin
                    // Claim/Complete: 块内 +0x84
                    is_target_claim = 1'b1;
                end
            end
        endcase
    end

    // ========================================================================
    // IRQ 输入同步 (参数化级数, 0 = 旁路)
    // ========================================================================
    Cdc_Sync #(
        .WIDTH      (NUM_SOURCES),
        .RESET_VAL  ('0),
        .DELAY_STAGES(SYNC_STAGES)
    ) u_sync (
        .dst_clk   (PCLK),
        .dst_rst_n (PRESETn),
        .async_sig (irq_i),
        .sync_sig  (irq_synced)
    );

    // ========================================================================
    // Gateway 实例化 (每源一个, source 0 也例化但 irq_i[0] 应接 0)
    // ========================================================================
    genvar g_src;
    generate
        for (g_src = 0; g_src < NUM_SOURCES; g_src++) begin : gen_gateway
            plic_gateway #(
                .TRIGGER_MODE(0)  // 默认电平触发
            ) u_gateway (
                .clk       (PCLK),
                .rst_n     (PRESETn),
                .irq_source(irq_synced[g_src]),
                .claim     (gateway_claim[g_src]),
                .complete  (gateway_complete[g_src]),
                .pending   (pending_bits[g_src])
            );
        end
    endgenerate

    // ========================================================================
    // 各源 claim/complete 脉冲聚合 (多目标时 OR 所有 target)
    // ========================================================================
    always_comb begin
        gateway_claim    = '0;
        gateway_complete = '0;
        for (int ti = 0; ti < NUM_TARGETS; ti++) begin
            gateway_claim    = gateway_claim    | target_claim_vec[ti];
            gateway_complete = gateway_complete | target_complete_vec[ti];
        end
    end

    // ========================================================================
    // 优先级寄存器 (WARL: 0..MAX_PRIORITY)
    // source 0 硬连线为 0
    // ========================================================================
    generate
        for (g_src = 0; g_src < NUM_SOURCES; g_src++) begin : gen_prio_reg
            always_ff @(posedge PCLK or negedge PRESETn) begin
                if (!PRESETn) begin
                    prio_regs[g_src] <= '0;
                end else if (wr_en && is_prio && (src_idx == g_src)) begin
                    if (g_src == 0) begin
                        prio_regs[0] <= '0;  // source 0 始终为 0
                    end else begin
                        prio_regs[g_src] <= (PWDATA[PRIO_WIDTH-1:0] <= MAX_PRIORITY[PRIO_WIDTH-1:0])
                                           ? PWDATA[PRIO_WIDTH-1:0]
                                           : MAX_PRIORITY[PRIO_WIDTH-1:0];
                    end
                end
            end
        end
    endgenerate

    // ========================================================================
    // 使能寄存器 (每目标每源一位, 位于 Target 块内 +0x00 ~ +0x7C)
    // ========================================================================
    genvar g_tgt, g_en_bit;
    generate
        for (g_tgt = 0; g_tgt < NUM_TARGETS; g_tgt++) begin : gen_enable_target
            for (g_en_bit = 0; g_en_bit < NUM_SOURCES; g_en_bit++) begin : gen_enable_bit
                logic [4:0] bit_idx;
                logic [4:0] src_word;

                assign bit_idx     = g_en_bit[4:0];
                assign src_word    = g_en_bit[9:5];

                always_ff @(posedge PCLK or negedge PRESETn) begin
                    if (!PRESETn) begin
                        enable_bits[g_tgt][g_en_bit] <= 1'b0;
                    end else if (is_target_enable && wr_en && (tgt_idx == g_tgt)) begin
                        if (word_idx == src_word && PSTRB[bit_idx[4:3]]) begin
                            enable_bits[g_tgt][g_en_bit] <= PWDATA[bit_idx];
                        end
                    end
                end
            end
        end
    endgenerate

    // ========================================================================
    // 阈值寄存器 (每目标一个, WARL, 位于 Target 块内 +0x80)
    // ========================================================================
    generate
        for (g_tgt = 0; g_tgt < NUM_TARGETS; g_tgt++) begin : gen_threshold
            always_ff @(posedge PCLK or negedge PRESETn) begin
                if (!PRESETn) begin
                    threshold_q[g_tgt] <= '0;
                end else if (is_target_threshold && wr_en && (tgt_idx == g_tgt)) begin
                    threshold_q[g_tgt] <= (PWDATA[PRIO_WIDTH-1:0] <= MAX_PRIORITY[PRIO_WIDTH-1:0])
                                         ? PWDATA[PRIO_WIDTH-1:0]
                                         : MAX_PRIORITY[PRIO_WIDTH-1:0];
                end
            end
        end
    endgenerate

    // ========================================================================
    // CompareTree 优先级仲裁 (每 target 独立一套)
    // 每个 target 用自己的 enable 和 threshold 过滤输入,
    // 共享同一个 CompareTree 参数, generate 例化 NUM_TARGETS 个
    // ========================================================================
    genvar g_arb;
    generate
        for (g_arb = 0; g_arb < NUM_TARGETS; g_arb++) begin : gen_arbiter

            // 构造 CompareTree 输入: 只包含 pending & enable & prio > threshold 的源
            always_comb begin
                ct_input_data[g_arb] = '0;
                for (int i = 0; i < CT_NUM; i++) begin
                    if (i < NUM_SOURCES) begin
                        ct_input_data[g_arb][PRIO_WIDTH*i +: PRIO_WIDTH] =
                            (pending_bits[i] && enable_bits[g_arb][i] && (prio_regs[i] > threshold_q[g_arb]))
                            ? prio_regs[i] : '0;
                    end
                end
            end

            CompareTree #(
                .DATA_WIDTH (PRIO_WIDTH),
                .DATA_NUM   (CT_NUM),
                .SIGNED     (0)             // 无符号比较
            ) u_compare_tree (
                .input_data (ct_input_data[g_arb]),
                .out_max    (ct_max_prio_comb[g_arb]),
                .max_index  (ct_max_idx_comb[g_arb])
            );

            always_ff @(posedge PCLK) begin
                ct_max_prio_r[g_arb] <= ct_max_prio_comb[g_arb];
                ct_max_idx_r[g_arb]  <= ct_max_idx_comb[g_arb];
            end

            // 提取胜出源 ID 和优先级, 判断有效性
            always_comb begin
                irq_valid[g_arb]   = 1'b0;
                winner_idx[g_arb]  = '0;
                winner_prio[g_arb] = '0;
                if (ct_max_prio_r[g_arb] != '0 && ct_max_idx_r[g_arb] < NUM_SOURCES) begin
                    if (pending_bits[ct_max_idx_r[g_arb]]
                        && enable_bits[g_arb][ct_max_idx_r[g_arb]]
                        && (prio_regs[ct_max_idx_r[g_arb]] > threshold_q[g_arb])) begin
                        irq_valid[g_arb]   = 1'b1;
                        winner_idx[g_arb]  = SRC_ID_WIDTH'(ct_max_idx_r[g_arb]);
                        winner_prio[g_arb] = ct_max_prio_r[g_arb];
                    end
                end
            end

        end
    endgenerate

    // ========================================================================
    // Target 实例化 (每目标一个)
    // ========================================================================
    generate
        for (g_tgt = 0; g_tgt < NUM_TARGETS; g_tgt++) begin : gen_target
            plic_target #(
                .NUM_SOURCES    (NUM_SOURCES),
                .MAX_PRIORITY (MAX_PRIORITY)
            ) u_target (
                .clk            (PCLK),
                .rst_n          (PRESETn),
                .max_id         (winner_idx[g_tgt]),
                .max_prio       (winner_prio[g_tgt]),
                .irq_valid      (irq_valid[g_tgt]),
                .claim_read     (target_claim_read[g_tgt]),
                .complete_write (target_complete_write[g_tgt]),
                .complete_id    (target_complete_id[g_tgt]),
                .claim_vec      (target_claim_vec[g_tgt]),
                .complete_vec   (target_complete_vec[g_tgt]),
                .claimed_id     (target_claimed_id[g_tgt]),
                .eip            (target_eip[g_tgt])
            );
            always_ff @(posedge PCLK) begin
                irq_o[g_tgt] <= target_eip[g_tgt];
            end
        end
    endgenerate

    // ========================================================================
    // Claim/Complete 脉冲生成 (来自 APB 访问)
    // ========================================================================
    generate
        for (g_tgt = 0; g_tgt < NUM_TARGETS; g_tgt++) begin : gen_cc_pulse
            assign target_claim_read[g_tgt]     = is_target_claim && rd_en && (tgt_idx == g_tgt);
            assign target_complete_write[g_tgt] = is_target_claim && wr_en && (tgt_idx == g_tgt);
            assign target_complete_id[g_tgt]    = PWDATA[SRC_ID_WIDTH-1:0];
        end
    endgenerate

    // ========================================================================
    // 读数据选择
    // ========================================================================
    always_ff @(posedge PCLK) begin
        if (is_prio) begin
            // Priority 寄存器读
            if (src_idx < NUM_SOURCES)
                PRDATA[PRIO_WIDTH-1:0] <= prio_regs[src_idx];

        end else if (is_pending) begin
            // Pending 位读 (只读, 每 word 32 位)
            for (int loop_bit = 0; loop_bit < 32; loop_bit++) begin
                int loop_src;
                loop_src = word_idx * 32 + loop_bit;
                if (loop_src < NUM_SOURCES)
                    PRDATA[loop_bit] <= pending_bits[loop_src];
            end

        end else if (is_target_enable) begin
            // Enable 位读 (Target 块内)
            if (tgt_idx < NUM_TARGETS) begin
                for (int loop_bit = 0; loop_bit < 32; loop_bit++) begin
                    int loop_src;
                    loop_src = word_idx * 32 + loop_bit;
                    if (loop_src < NUM_SOURCES)
                        PRDATA[loop_bit] <= enable_bits[tgt_idx][loop_src];
                end
            end

        end else if (is_target_threshold) begin
            // Threshold 读
            if (tgt_idx < NUM_TARGETS)
                PRDATA[PRIO_WIDTH-1:0] <= threshold_q[tgt_idx];

        end else if (is_target_claim) begin
            // Claim 读: 返回对应 target 的 claimed_id
            if (tgt_idx < NUM_TARGETS)
                PRDATA <= {{(32-SRC_ID_WIDTH){1'b0}}, target_claimed_id[tgt_idx]};
        end else begin
            PRDATA <= 32'h0;
        end
    end

endmodule
