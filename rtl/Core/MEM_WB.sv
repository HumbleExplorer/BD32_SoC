`include "./../SoC_Config.sv"
`include "./../RV32_inst_Define.sv"
timeunit 1ns;
timeprecision 1ps;
module MEM_WB #(
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
    // to ctrl
    // output  logic                           jump_en,
    // output  logic   [ADDR_WIDTH-1:0]        jump_addr,
    // to wb
    output  logic   [DATA_WIDTH-1:0]        inst_o,
    output  logic   [ADDR_WIDTH-1:0]        inst_addr_o,
    output  logic                           reg_rd_wen_o,
    output  logic   [REG_ADDR_WIDTH-1:0]    reg_rd_waddr_o,
    output  logic   [DATA_WIDTH-1:0]        reg_rd_wdata_o
`ifdef DISPLAY_INST_WAVE
    ,
    output  logic   [ADDR_WIDTH-1:0]        inst_addr_display_o,
`endif
    input   logic   [2:0]                   inst_type_i,
    output  logic   [2:0]                   inst_type_o,
    input   logic                           valid_i,
    output  logic                           valid_o
);

always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        inst_addr_o     <= #1 {`BOOT_BASE_TAG,{BLOCK_SIZE_WIDTH{1'b0}}};
        inst_o          <= #1 `INST_NOP;
        reg_rd_wen_o    <= #1 1'b0;
        reg_rd_waddr_o  <= #1 'h0;
        reg_rd_wdata_o  <= #1 'h0;
        inst_type_o     <= #1 3'd0;
    end else if(flush) begin
        inst_o          <= #1 `INST_NOP;
        reg_rd_wen_o    <= #1 1'b0;
        reg_rd_waddr_o  <= #1 'h0;
        reg_rd_wdata_o  <= #1 'h0;
        inst_type_o     <= #1 3'd0;
    end else if(!stall) begin//指令地址无需清零
        inst_addr_o     <= #1 inst_addr_i;
        inst_o          <= #1 inst_i;
        reg_rd_wen_o    <= #1 reg_rd_wen_i;
        reg_rd_waddr_o  <= #1 reg_rd_waddr_i;
        reg_rd_wdata_o  <= #1 reg_rd_wdata_i;
        inst_type_o     <= #1 inst_type_i;
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

endmodule
