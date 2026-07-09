`include "./../SoC_Config.sv"
`include "./../RV32_inst_Define.sv"
timeunit 1ns;
timeprecision 1ps;
module Mem_Access #(
    parameter ADDR_WIDTH = `ADDR_WIDTH,
    parameter DATA_WIDTH = `DATA_WIDTH,
    localparam BLOCK_SIZE_WIDTH = ADDR_WIDTH - `DEVICE_TAG_WIDTH
)(
    input   logic                       clk,
    input   logic                       rst_n,
    input   logic   [ADDR_WIDTH-1:0]    access_addr,
    input   logic                       access_en,
    input   logic                       access_wr,
    input   logic                       bus_tran_done,
    input   logic   [DATA_WIDTH-1:0]    dtcm_rdata,
    input   logic   [DATA_WIDTH-1:0]    rd_bus_data,
    input   logic   [2:0]               access_func3,

    //to dtcm/bus
    output  logic                       dtcm_sel,
    output  logic                       bus_sel,
    //to Mux (func3 expanded data, only for load instructions)
    output  logic   [DATA_WIDTH-1:0]    func3_expanded_data,
    // 锁存后的 load valid 信号，在 stall 周期保持数据选择正确
    output  logic                       dtcm_rvalid,
    output  logic                       bus_rvalid
);

logic [DATA_WIDTH-1:0] access_rdata;

assign dtcm_sel     = access_en & (access_addr[ADDR_WIDTH-1:BLOCK_SIZE_WIDTH] == `DTCM_BASE_TAG) ;
assign bus_sel      = access_en & (access_addr[ADDR_WIDTH-1:BLOCK_SIZE_WIDTH] >= `BUS_BASE_ADDR) ;

// ============================================
// dtcm_rvalid / bus_rvalid 锁存
// 在 stall 周期保持有效，确保数据选择和 func3 扩展正确
// ============================================
logic        dtcm_rvalid_q;
logic [2:0]  access_func3_r;
logic [1:0]  access_byte_r;

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        dtcm_rvalid_q  <= #1 1'b0;
        access_func3_r <= #1 '0;
        access_byte_r  <= #1 '0;
    end else begin
        // dtcm_rvalid: 在访问开始时锁存，下一拍自动清除（DTCM 同步读 1 拍延迟）
        dtcm_rvalid_q <= #1 (access_en && ~access_wr && dtcm_sel);

        // 锁存 func3 和地址低位（用于 stall 周期保持正确 func3 扩展）
        if (access_en  && ~access_wr && (dtcm_sel || bus_sel)) begin
            access_func3_r <= #1 access_func3;
            access_byte_r  <= #1 access_addr[1:0];
        end
    end
end

assign dtcm_rvalid = dtcm_rvalid_q;
assign bus_rvalid  = ~access_wr && bus_tran_done;

// 读数据选择：使用锁存后的 valid 信号，在 stall 周期仍能正确选择数据源
assign access_rdata = dtcm_rvalid ? dtcm_rdata :
                     bus_rvalid  ? rd_bus_data  : '0;

// 符号扩展：使用锁存后的 func3 和地址低位，在 stall 周期保持正确
always_comb begin
    if (dtcm_rvalid | bus_rvalid) begin
        case (access_func3_r)
            `INST_LB : begin
                case (access_byte_r)
                    2'b00:func3_expanded_data = {{24{access_rdata[7]}},access_rdata[7:0]};
                    2'b01:func3_expanded_data = {{24{access_rdata[15]}},access_rdata[15:8]};
                    2'b10:func3_expanded_data = {{24{access_rdata[23]}},access_rdata[23:16]};
                    2'b11:func3_expanded_data = {{24{access_rdata[31]}},access_rdata[31:24]};
                    default:func3_expanded_data = {{24{access_rdata[7]}},access_rdata[7:0]};
                endcase
            end
            `INST_LH : begin
                case (access_byte_r[1])
                    1'b0:func3_expanded_data = {{16{access_rdata[15]}},access_rdata[15:0]};
                    1'b1:func3_expanded_data = {{16{access_rdata[31]}},access_rdata[31:16]};
                    default:func3_expanded_data = {{16{access_rdata[15]}},access_rdata[15:0]};
                endcase
            end
            `INST_LW : begin
                func3_expanded_data = access_rdata;
            end
            `INST_LBU : begin
                case (access_byte_r)
                    2'b00:func3_expanded_data = {24'h0,access_rdata[7:0]};
                    2'b01:func3_expanded_data = {24'h0,access_rdata[15:8]};
                    2'b10:func3_expanded_data = {24'h0,access_rdata[23:16]};
                    2'b11:func3_expanded_data = {24'h0,access_rdata[31:24]};
                    default:func3_expanded_data = {24'h0,access_rdata[7:0]};
                endcase
            end
            `INST_LHU : begin
                case (access_byte_r[1])
                    1'b0:func3_expanded_data = {16'h0,access_rdata[15:0]};
                    1'b1:func3_expanded_data = {16'h0,access_rdata[31:16]};
                    default:func3_expanded_data = {16'h0,access_rdata[15:0]};
                endcase
            end
            default : func3_expanded_data = '0;
        endcase
    end else begin
        func3_expanded_data = '0;
    end
end


endmodule
