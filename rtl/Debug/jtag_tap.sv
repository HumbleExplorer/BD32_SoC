// ============================================================================
// jtag_tap.sv — JTAG TAP + DTM（Debug Transport Module）
//
// BD32 — RV32IM Pipelined RISC-V SoC
// Copyright (c) 2026 BD32 Project
// SPDX-License-Identifier: Apache-2.0
//
// 改编自 SparrowRV jtag_driver.v（MIT License）：
//   Copyright (c) 2022 xiaowuzxc, https://github.com/xiaowuzxc/SparrowRV
//   修改说明：dmireset/dmihardreset 分离、dmistat busy=3、IDCODE/IR 定制
// ============================================================================
// BD32 JTAG TAP + DTM (Debug Transport Module)
// 实现 IEEE 1149.1 TAP 状态机 + RISC-V Debug Spec 1.0 DMI 接口
`include "./../SoC_Config.sv"
timeunit 1ns;
timeprecision 1ps;

module jtag_tap #(
    parameter DMI_ADDR_BITS = 6,
    parameter DMI_DATA_BITS = 32,
    parameter DMI_OP_BITS   = 2,
    parameter DMI_BITS      = DMI_ADDR_BITS + DMI_DATA_BITS + DMI_OP_BITS  // 40
)(
    input  logic                    rst_n,
    // JTAG 引脚
    input  logic                    tck,
    input  logic                    tms,
    input  logic                    tdi,
    output logic                    tdo,
    // DM 侧 CDC 接口（req/ack 握手）
    // DTM → DM（请求）
    output logic                    dtm_req_valid,
    output logic [DMI_BITS-1:0]     dtm_req_data,
    input  logic                    dm_req_ack,
    // DM → DTM（响应）
    input  logic                    dm_resp_valid,
    input  logic [DMI_BITS-1:0]     dm_resp_data,
    output logic                    dtm_resp_ack
);

// ============================================================
// IDCODE: BD32 自定义
// [31:28] version = 4'h1
// [27:12] part number = 16'hBD32
// [11:1]  manufacturer = 11'h001 (自定义)
// [0]     = 1'b1 (JTAG 标准要求)
// ============================================================
localparam [31:0] IDCODE = {4'h1, 16'hBD32, 11'h001, 1'b1};
localparam DTM_VERSION = 4'h1;  // dtmcs.version=1（Spec 0.13 与 1.0 相同）

// IR 寄存器定义
localparam IR_BITS      = 5;
localparam REG_BYPASS   = 5'b11111;
localparam REG_IDCODE   = 5'b00001;
localparam REG_DTMCS    = 5'b10000;
localparam REG_DMI      = 5'b10001;

// TAP 状态
localparam TEST_LOGIC_RESET = 4'h0;
localparam RUN_TEST_IDLE    = 4'h1;
localparam SELECT_DR        = 4'h2;
localparam CAPTURE_DR       = 4'h3;
localparam SHIFT_DR         = 4'h4;
localparam EXIT1_DR         = 4'h5;
localparam PAUSE_DR         = 4'h6;
localparam EXIT2_DR         = 4'h7;
localparam UPDATE_DR        = 4'h8;
localparam SELECT_IR        = 4'h9;
localparam CAPTURE_IR       = 4'hA;
localparam SHIFT_IR         = 4'hB;
localparam EXIT1_IR         = 4'hC;
localparam PAUSE_IR         = 4'hD;
localparam EXIT2_IR         = 4'hE;
localparam UPDATE_IR        = 4'hF;

// 内部寄存器
logic [3:0]             tap_state;
logic [IR_BITS-1:0]     ir_reg;
logic [DMI_BITS-1:0]    shift_reg;
logic                   sticky_busy;
logic                   dm_is_busy;
logic [DMI_BITS-1:0]    dm_resp_latch;
logic                   req_valid_r;
logic [DMI_BITS-1:0]    req_data_r;

// CDC 握手信号
logic                   tx_idle;
logic                   rx_valid;
logic [DMI_BITS-1:0]    rx_data;

// 组合逻辑
wire is_busy = sticky_busy | dm_is_busy;
// dtmcs.dmistat（Debug Spec 1.0）：0=success，3=busy（sticky）
wire [1:0] dmi_stat = is_busy ? 2'b11 : 2'b00;
// dtmcs 写位：bit16=dmireset（只清 sticky 错误），bit17=dtmhardreset（忘掉所有未完成事务）
wire dtm_reset      = shift_reg[16];
wire dtm_hard_reset = shift_reg[17];

wire [31:0] dtmcs = {14'b0,
                     1'b0,              // dmihardreset
                     1'b0,              // dmireset
                     1'b0,
                     3'h5,              // idle cycles
                     dmi_stat,          // dmistat
                     DMI_ADDR_BITS[5:0],// abits
                     DTM_VERSION};      // version

wire [DMI_BITS-1:0] busy_response = {{(DMI_ADDR_BITS + DMI_DATA_BITS){1'b0}}, {DMI_OP_BITS{1'b1}}};

// ============================================================
// TAP 状态机
// ============================================================
always_ff @(posedge tck or negedge rst_n) begin
    if (!rst_n)
        tap_state <= TEST_LOGIC_RESET;
    else begin
        case (tap_state)
            TEST_LOGIC_RESET: tap_state <= tms ? TEST_LOGIC_RESET : RUN_TEST_IDLE;
            RUN_TEST_IDLE:    tap_state <= tms ? SELECT_DR        : RUN_TEST_IDLE;
            SELECT_DR:        tap_state <= tms ? SELECT_IR        : CAPTURE_DR;
            CAPTURE_DR:       tap_state <= tms ? EXIT1_DR         : SHIFT_DR;
            SHIFT_DR:         tap_state <= tms ? EXIT1_DR         : SHIFT_DR;
            EXIT1_DR:         tap_state <= tms ? UPDATE_DR        : PAUSE_DR;
            PAUSE_DR:         tap_state <= tms ? EXIT2_DR         : PAUSE_DR;
            EXIT2_DR:         tap_state <= tms ? UPDATE_DR        : SHIFT_DR;
            UPDATE_DR:        tap_state <= tms ? SELECT_DR        : RUN_TEST_IDLE;
            SELECT_IR:        tap_state <= tms ? TEST_LOGIC_RESET : CAPTURE_IR;
            CAPTURE_IR:       tap_state <= tms ? EXIT1_IR         : SHIFT_IR;
            SHIFT_IR:         tap_state <= tms ? EXIT1_IR         : SHIFT_IR;
            EXIT1_IR:         tap_state <= tms ? UPDATE_IR        : PAUSE_IR;
            PAUSE_IR:         tap_state <= tms ? EXIT2_IR         : PAUSE_IR;
            EXIT2_IR:         tap_state <= tms ? UPDATE_IR        : SHIFT_IR;
            UPDATE_IR:        tap_state <= tms ? SELECT_DR        : RUN_TEST_IDLE;
            default:          tap_state <= TEST_LOGIC_RESET;
        endcase
    end
end

// ============================================================
// IR/DR 移位
// ============================================================
always_ff @(posedge tck) begin
    case (tap_state)
        CAPTURE_IR: shift_reg <= {{(DMI_BITS-1){1'b0}}, 1'b1};
        SHIFT_IR:   shift_reg <= {{(DMI_BITS-IR_BITS){1'b0}}, tdi, shift_reg[IR_BITS-1:1]};
        CAPTURE_DR: case (ir_reg)
                        REG_IDCODE: shift_reg <= {{(DMI_BITS-32){1'b0}}, IDCODE};
                        REG_DTMCS:  shift_reg <= {{(DMI_BITS-32){1'b0}}, dtmcs};
                        REG_DMI:    shift_reg <= is_busy ? busy_response : dm_resp_latch;
                        default:    shift_reg <= '0;  // BYPASS
                    endcase
        SHIFT_DR:   case (ir_reg)
                        REG_IDCODE: shift_reg <= {{(DMI_BITS-32){1'b0}}, tdi, shift_reg[31:1]};
                        REG_DTMCS:  shift_reg <= {{(DMI_BITS-32){1'b0}}, tdi, shift_reg[31:1]};
                        REG_DMI:    shift_reg <= {tdi, shift_reg[DMI_BITS-1:1]};
                        default:    shift_reg <= {{(DMI_BITS-1){1'b0}}, tdi};
                    endcase
        default: ;
    endcase
end

// ============================================================
// IR 更新（TCK 下降沿）
// ============================================================
always_ff @(negedge tck) begin
    if (tap_state == TEST_LOGIC_RESET)
        ir_reg <= REG_IDCODE;
    else if (tap_state == UPDATE_IR)
        ir_reg <= shift_reg[IR_BITS-1:0];
end

// ============================================================
// TDO 输出（TCK 下降沿）
// ============================================================
always_ff @(negedge tck) begin
    if (tap_state == SHIFT_IR || tap_state == SHIFT_DR)
        tdo <= shift_reg[0];
    else
        tdo <= 1'b0;
end

// ============================================================
// DMI 请求发起
// ============================================================
always_ff @(posedge tck or negedge rst_n) begin
    if (!rst_n) begin
        req_valid_r <= 1'b0;
        req_data_r  <= '0;
    end else begin
        if (tap_state == UPDATE_DR && ir_reg == REG_DMI && !is_busy && tx_idle) begin
            req_valid_r <= 1'b1;
            req_data_r  <= shift_reg;
        end else begin
            req_valid_r <= 1'b0;
        end
    end
end

// ============================================================
// sticky_busy 管理
// ============================================================
always_ff @(posedge tck or negedge rst_n) begin
    if (!rst_n)
        sticky_busy <= 1'b0;
    else if (tap_state == UPDATE_DR && ir_reg == REG_DTMCS && (dtm_reset || dtm_hard_reset))
        sticky_busy <= 1'b0;
    else if (tap_state == CAPTURE_DR && ir_reg == REG_DMI)
        sticky_busy <= is_busy;
end

// ============================================================
// DM 响应锁存 + busy 管理
// ============================================================
always_ff @(posedge tck or negedge rst_n) begin
    if (!rst_n) begin
        dm_resp_latch <= '0;
        dm_is_busy    <= 1'b0;
    end else if (tap_state == UPDATE_DR && ir_reg == REG_DTMCS && dtm_hard_reset) begin
        // dtmhardreset：忘记所有未完成 DMI 事务（含进行中事务与响应锁存）
        dm_resp_latch <= '0;
        dm_is_busy    <= 1'b0;
    end else begin
        if (rx_valid)
            dm_resp_latch <= rx_data;
        if (req_valid_r)
            dm_is_busy <= 1'b1;
        else if (rx_valid)
            dm_is_busy <= 1'b0;
    end
end

// ============================================================
// CDC：DTM(TCK域) → DM(clk域)
// ============================================================
debug_cdc_tx #(.DW(DMI_BITS)) u_tx (
    .clk        (tck),
    .rst_n      (rst_n),
    .ack_i      (dm_req_ack),
    .req_i      (req_valid_r),
    .req_data_i (req_data_r),
    .idle_o     (tx_idle),
    .req_o      (dtm_req_valid),
    .req_data_o (dtm_req_data)
);

// CDC：DM(clk域) → DTM(TCK域)
debug_cdc_rx #(.DW(DMI_BITS)) u_rx (
    .clk         (tck),
    .rst_n       (rst_n),
    .req_i       (dm_resp_valid),
    .req_data_i  (dm_resp_data),
    .ack_o       (dtm_resp_ack),
    .recv_data_o (rx_data),
    .recv_rdy_o  (rx_valid)
);

endmodule
