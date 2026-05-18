`include "./../SoC_Config.sv"
`include "./../RV32_inst_Define.sv"
`timescale 1ns / 1ps
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
    input   logic   [DATA_WIDTH-1:0]    rd_dtcm_data,
    input   logic   [DATA_WIDTH-1:0]    rd_bus_data,
    input   logic   [2:0]               rd_mem_func3,

    //to dtcm/bus
    output  logic                       dtcm_sel,
    output  logic                       bus_sel,
    //to crtl
    output  logic                       mem_access_ready,
    output  logic   [DATA_WIDTH-2:0]    exception_code,
    output  logic   [DATA_WIDTH-1:0]    exception_val,
    //to Mux (func3 expanded data, only for load instructions)
    output  logic   [DATA_WIDTH-1:0]    func3_expanded_data,
    // 锁存后的 load valid 信号，在 stall 周期保持数据选择正确
    output  logic                       dtcm_rvalid,
    output  logic                       bus_rvalid
);

logic [DATA_WIDTH-1:0] rd_mem_data;
logic                  access_illegal;

assign dtcm_sel     = access_en & (access_addr[ADDR_WIDTH-1:BLOCK_SIZE_WIDTH] == `DTCM_BASE_TAG) ;
assign bus_sel      = access_en & (access_addr[ADDR_WIDTH-1:BLOCK_SIZE_WIDTH] >= `BUS_BASE_ADDR) ;
assign access_illegal = access_en ? (access_addr[ADDR_WIDTH-1:BLOCK_SIZE_WIDTH] < `DTCM_BASE_TAG): 1'b0;

// ============================================
// 同步读模式：BRAM 采样地址后下一拍输出数据
// mem_access_ready 简化：DTCM 无需等待信号，总线等 bus_tran_done
// 地址→数据同步在 Core 层由 MUX2 和 load-use stall 处理
// ============================================

// mem_access_ready：
// - 总线访问：等待 bus_tran_done
// - DTCM：始终 ready（数据在地址送出的下一拍由 MEM/WB 直接捕获）
assign mem_access_ready = bus_sel ? bus_tran_done : 1'b1;

// ============================================
// dtcm_rvalid / bus_rvalid 锁存
// 在 stall 周期保持有效，确保数据选择和 func3 扩展正确
// ============================================
logic        dtcm_rvalid_q;
logic        bus_rvalid_q;
logic [2:0]  rd_mem_func3_r;
logic [1:0]  access_byte_r;

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        dtcm_rvalid_q  <= 1'b0;
        bus_rvalid_q   <= 1'b0;
        rd_mem_func3_r <= '0;
        access_byte_r  <= '0;
    end else begin
        // dtcm_rvalid: 在访问开始时锁存，下一拍自动清除（DTCM 同步读 1 拍延迟）
        dtcm_rvalid_q <= (access_en && ~access_wr && dtcm_sel);
            
        // bus_rvalid: 在访问开始时锁存，bus_tran_done 时清除
        if (access_en && ~access_wr && bus_sel)
            bus_rvalid_q <= ~bus_tran_done;
            
        // 锁存 func3 和地址低位（用于 stall 周期保持正确 func3 扩展）
        if (access_en  && ~access_wr && (dtcm_sel || bus_sel)) begin
            rd_mem_func3_r <= rd_mem_func3;
            access_byte_r  <= access_addr[1:0];
        end
    end
end

assign dtcm_rvalid = dtcm_rvalid_q;
assign bus_rvalid  = bus_rvalid_q;

// 读数据选择：使用锁存后的 valid 信号，在 stall 周期仍能正确选择数据源
assign rd_mem_data = dtcm_rvalid_q ? rd_dtcm_data : 
                     bus_rvalid_q  ? rd_bus_data  : '0;

assign exception_code = access_illegal ? (access_wr ? 4'd7 : 4'd5) : {DATA_WIDTH-1{1'b1}};
assign exception_val = access_addr;

// 符号扩展：使用锁存后的 func3 和地址低位，在 stall 周期保持正确
always_comb begin
    if (dtcm_rvalid_q | bus_rvalid_q) begin
        case (rd_mem_func3_r)
            `INST_LB : begin
                case (access_byte_r)
                    2'b00:func3_expanded_data = {{24{rd_mem_data[7]}},rd_mem_data[7:0]};
                    2'b01:func3_expanded_data = {{24{rd_mem_data[15]}},rd_mem_data[15:8]};
                    2'b10:func3_expanded_data = {{24{rd_mem_data[23]}},rd_mem_data[23:16]};
                    2'b11:func3_expanded_data = {{24{rd_mem_data[31]}},rd_mem_data[31:24]};
                    default:func3_expanded_data = {{24{rd_mem_data[7]}},rd_mem_data[7:0]};
                endcase
            end
            `INST_LH : begin
                case (access_byte_r[1])
                    1'b0:func3_expanded_data = {{16{rd_mem_data[15]}},rd_mem_data[15:0]};
                    1'b1:func3_expanded_data = {{16{rd_mem_data[31]}},rd_mem_data[31:16]};
                    default:func3_expanded_data = {{16{rd_mem_data[15]}},rd_mem_data[15:0]};
                endcase
            end
            `INST_LW : begin
                func3_expanded_data = rd_mem_data;
            end
            `INST_LBU : begin
                case (access_byte_r)
                    2'b00:func3_expanded_data = {24'h0,rd_mem_data[7:0]};
                    2'b01:func3_expanded_data = {24'h0,rd_mem_data[15:8]};
                    2'b10:func3_expanded_data = {24'h0,rd_mem_data[23:16]};
                    2'b11:func3_expanded_data = {24'h0,rd_mem_data[31:24]};
                    default:func3_expanded_data = {24'h0,rd_mem_data[7:0]};
                endcase
            end
            `INST_LHU : begin
                case (access_byte_r[1])
                    1'b0:func3_expanded_data = {16'h0,rd_mem_data[15:0]};
                    1'b1:func3_expanded_data = {16'h0,rd_mem_data[31:16]};
                    default:func3_expanded_data = {16'h0,rd_mem_data[15:0]};
                endcase
            end
            default : func3_expanded_data = '0;
        endcase
    end else begin
        func3_expanded_data = '0;
    end
end


endmodule
