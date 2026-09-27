`include "./../SoC_Config.sv"
`include "./../RV32_inst_Define.sv"
timeunit 1ns;
timeprecision 1ps;
module EX_MEM #(
    parameter ADDR_WIDTH = `ADDR_WIDTH,
    parameter DATA_WIDTH = `DATA_WIDTH,
    parameter REG_ADDR_WIDTH = `REG_ADDR_WIDTH,
    localparam BLOCK_SIZE_WIDTH = ADDR_WIDTH - `DEVICE_TAG_WIDTH
 )(
    input   logic                           clk,
    input   logic                           rst_n,
    input   logic                           stall,
    input   logic                           flush,
    // from execute
    input   logic   [ADDR_WIDTH-1:0]        inst_addr_i,
    input   logic   [DATA_WIDTH-1:0]        inst_i,
    input   logic                           reg_rd_wen_i,
    input   logic   [REG_ADDR_WIDTH-1:0]    reg_rd_waddr_i,
    input   logic   [DATA_WIDTH-1:0]        reg_rd_wdata_i,
    input   logic                           access_en_i,
    input   logic                           access_wr_i,

    // to mem
    output  logic   [ADDR_WIDTH-1:0]        inst_addr_o,
    output  logic   [DATA_WIDTH-1:0]        inst_o,
    output  logic                           access_en_o,
    output  logic                           access_wr_o,
    // to wb
    output  logic                           reg_rd_wen_o,
    (* MAX_FANOUT = 16 *) output  logic   [REG_ADDR_WIDTH-1:0]    reg_rd_waddr_o,
    output  logic   [DATA_WIDTH-1:0]        reg_rd_wdata_o,
`ifdef DISPLAY_INST_WAVE
    output  logic   [ADDR_WIDTH-1:0]        inst_addr_display_o,
`endif

    input   logic   [2:0]                   inst_type_i,
    output  logic   [2:0]                   inst_type_o,
    input   logic                           zcmp_micro_last_i,
    output  logic                           zcmp_micro_last_o,
    input   logic                           zcmp_micro_any_i,
    output  logic                           zcmp_micro_any_o,
    input   logic                           zcb_tag_i,
    output  logic                           zcb_tag_o,
    input   logic                           valid_i,
    output  logic                           valid_o
);

always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        inst_addr_o     <= #1 {`BOOT_BASE_TAG,{BLOCK_SIZE_WIDTH{1'b0}}};
        inst_o          <= #1 `INST_NOP;
        access_en_o     <= #1 1'b0;
        access_wr_o     <= #1 1'b0;
        reg_rd_wen_o    <= #1 1'b0;
        reg_rd_waddr_o  <= #1 'h0;
        reg_rd_wdata_o  <= #1 'h0;
    inst_type_o     <= #1 3'd0;
    zcmp_micro_last_o <= #1 1'b0;
    zcmp_micro_any_o  <= #1 1'b0;
    zcb_tag_o         <= #1 1'b0;
    end else begin
        if(flush) begin
            inst_o          <= #1 `INST_NOP;
            access_en_o     <= #1 1'b0;
            reg_rd_wen_o    <= #1 1'b0;
            // 冲刷时清残留 waddr/wdata：否则被取消指令的陈旧 waddr 会配合
            // 保持的 tcm_rvalid 强制写回（幽灵写回家族，breathing 崩溃根因）。
            reg_rd_waddr_o  <= #1 'h0;
            reg_rd_wdata_o  <= #1 'h0;
    inst_type_o     <= #1 3'd0;
    zcmp_micro_last_o <= #1 1'b0;
    zcmp_micro_any_o  <= #1 1'b0;
    zcb_tag_o         <= #1 1'b0;
        end else if(!stall) begin
            inst_addr_o     <= #1 inst_addr_i;
            inst_o          <= #1 inst_i;
            access_en_o     <= #1 access_en_i;
            access_wr_o     <= #1 access_wr_i;
            reg_rd_wen_o    <= #1 reg_rd_wen_i;
            reg_rd_waddr_o  <= #1 reg_rd_waddr_i;
            reg_rd_wdata_o  <= #1 reg_rd_wdata_i;
    inst_type_o     <= #1 inst_type_i;
    zcmp_micro_last_o <= #1 zcmp_micro_last_i;
    zcmp_micro_any_o  <= #1 zcmp_micro_any_i;
    zcb_tag_o         <= #1 zcb_tag_i;
        end
    end
end
`ifdef DISPLAY_INST_WAVE
always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        inst_addr_display_o <= #1 {`BOOT_BASE_TAG,{BLOCK_SIZE_WIDTH{1'b0}}};
    end else if(flush) begin
        inst_addr_display_o <= #1 {`BOOT_BASE_TAG,{BLOCK_SIZE_WIDTH{1'b0}}};
    end else if (!stall) begin
        inst_addr_display_o <= #1 inst_addr_i;
    end
end
`endif
always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n)           valid_o <= #1 1'b0;
    else if(flush)       valid_o <= #1 1'b0;
    else                 valid_o <= #1 ~stall & valid_i;
end

`ifndef SYNTHESIS
// ===== SVA：流水线寄存器控制一致性 =====
// flush 次拍指令有效位必须清零（边界指令死亡语义）
a_flush_clear: assert property (
    @(posedge clk) disable iff (!rst_n)
    (flush) |=> (!valid_o));
// stall（非 flush）时指令内容保持——字段由 !stall 门保持，不许漂移
a_stall_hold: assert property (
    @(posedge clk) disable iff (!rst_n)
    (stall && !flush) |=> ($stable(inst_o) && $stable(inst_addr_o)));
`endif

`ifdef ASSERT_MODULE
// ===== SVA L2：EX_MEM 深化——stall 保持覆盖访存/写回控制字段（L1 仅查 inst/addr）=====
// 进入 stall 的第一拍允许是新装载值（合法），stall 持续期间内容必须冻结
always @(posedge clk) begin
    if (rst_n && $past(rst_n) && $past(stall && !flush && valid_o)
        && stall && !flush && valid_o) begin
        a_l2_exmem_ctrl_hold: assert property (
            reg_rd_wen_o   == $past(reg_rd_wen_o) &&
            reg_rd_waddr_o == $past(reg_rd_waddr_o) &&
            reg_rd_wdata_o == $past(reg_rd_wdata_o) &&
            access_en_o    == $past(access_en_o) &&
            access_wr_o    == $past(access_wr_o) &&
            inst_type_o    == $past(inst_type_o) &&
            zcmp_micro_any_o  == $past(zcmp_micro_any_o) &&
            zcmp_micro_last_o == $past(zcmp_micro_last_o));
    end
end
`endif

endmodule
