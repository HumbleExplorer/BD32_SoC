`timescale 1ns / 1ps
// =============================================================================
// PLIC Target - 单目标 Claim/Complete 状态机
// 管理一个目标(hart)的 claim/complete 握手，输出 EIP 中断线
// 状态: IDLE -> CLAIMED (当 claim 成功时)
// 支持嵌套 claim: 已在 CLAIMED 状态时再次 claim 会更新 in_service_id
// =============================================================================
module plic_target #(
    parameter NUM_SOURCES = 16,
    parameter MAX_PRIORITY = 7,
    localparam SRC_ID_WIDTH = $clog2(NUM_SOURCES + 1),
    localparam PRIO_WIDTH   = $clog2(MAX_PRIORITY + 1)
)(
    input  logic                          clk,
    input  logic                          rst_n,

    // 来自优先级仲裁器
    input  logic [SRC_ID_WIDTH-1:0]       max_id,       // 当前最高优先级源 ID (0 = 无)
    input  logic [PRIO_WIDTH-1:0]         max_prio,     // 当前最高优先级值
    input  logic                          irq_valid,    // 有有效中断待处理

    // Claim/Complete 总线接口
    input  logic                          claim_read,    // 脉冲: 软件读取 claim 寄存器
    input  logic                          complete_write,// 脉冲: 软件写入 complete 寄存器
    input  logic [SRC_ID_WIDTH-1:0]       complete_id,   // 软件写入的完成源 ID

    // 输出到 Gateway
    output logic [NUM_SOURCES-1:0]        claim_vec,     // one-hot claim 脉冲
    output logic [NUM_SOURCES-1:0]        complete_vec,  // one-hot complete 脉冲

    // Claim 读数据
    output logic [SRC_ID_WIDTH-1:0]       claimed_id,    // 返回给软件的 claim ID

    // 外部中断输出
    output logic                          eip            // 外部中断 pending 输出
);

    // ========================================================================
    // 状态机定义
    // ========================================================================
    typedef enum logic [0:0] {
        ST_IDLE,
        ST_CLAIMED
    } state_t;

    state_t state, state_next;

    // ========================================================================
    // 内部信号
    // ========================================================================
    logic [SRC_ID_WIDTH-1:0] in_service_id, in_service_id_next;

    // ========================================================================
    // EIP 生成: 电平敏感，只要有符合条件的中断就置位
    // ========================================================================
    assign eip = irq_valid;

    // ========================================================================
    // 状态寄存器
    // ========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= ST_IDLE;
            in_service_id <= '0;
        end else begin
            state         <= state_next;
            in_service_id <= in_service_id_next;
        end
    end

    // ========================================================================
    // 次态与输出逻辑 (组合逻辑)
    // ========================================================================
    always_comb begin
        // 默认值
        state_next         = state;
        in_service_id_next = in_service_id;
        claim_vec          = '0;
        complete_vec       = '0;
        claimed_id         = '0;

        case (state)
            // ----------------------------------------------------------------
            // IDLE 状态: 等待软件 claim
            // ----------------------------------------------------------------
            ST_IDLE: begin
                if (claim_read) begin
                    if (irq_valid) begin
                        // 有有效中断: 进入 CLAIMED，发送 claim 脉冲
                        state_next         = ST_CLAIMED;
                        in_service_id_next = max_id;
                        claim_vec[max_id]  = 1'b1;
                        claimed_id         = max_id;
                    end else begin
                        // 无中断: 返回 0
                        claimed_id = '0;
                    end
                end
            end

            // ----------------------------------------------------------------
            // CLAIMED 状态: 已 claim 一个中断，等待 complete
            // ----------------------------------------------------------------
            ST_CLAIMED: begin
                if (claim_read) begin
                    if (irq_valid) begin
                        // 嵌套 claim: 更新 in_service_id，发送新 claim 脉冲
                        // 注意: 旧的 in_service_id 被覆盖，软件需自行管理嵌套
                        in_service_id_next = max_id;
                        claim_vec[max_id]  = 1'b1;
                        claimed_id         = max_id;
                    end else begin
                        // 无更高优先级中断，返回 0
                        claimed_id = '0;
                    end
                end else if (complete_write) begin
                    if (complete_id == in_service_id) begin
                        // 正确的 complete: 返回 IDLE，发送 complete 脉冲
                        state_next = ST_IDLE;
                        complete_vec[in_service_id] = 1'b1;
                        in_service_id_next = '0;
                    end
                    // else: ID 不匹配，忽略 (spec 定义为 undefined behavior)
                end
            end

            default: state_next = ST_IDLE;
        endcase
    end

endmodule
