`include "./../SoC_Config.sv"
`include "./../RV32_inst_Define.sv"
`timescale 1ns / 1ps
module Mem_Access #(//模块内的mem指所有用到load、store的部分
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
    input   logic   [DATA_WIDTH-1:0]    wr_reg_data_from_ex_mem,

    //to dtcm/bus
    output  logic                       dtcm_sel,
    output  logic                       bus_sel,
    //to crtl
    output  logic                       mem_access_ready,
    output  logic   [DATA_WIDTH-2:0]    exception_code,
    output  logic   [DATA_WIDTH-1:0]    exception_val,
    //to MEM/WB
    output  logic   [DATA_WIDTH-1:0]    wr_reg_data
);

logic [DATA_WIDTH-1:0] rd_mem_data;
logic                  access_illegal;

assign dtcm_sel     = access_en & (access_addr[ADDR_WIDTH-1:BLOCK_SIZE_WIDTH] == `DTCM_BASE_TAG) ;
assign bus_sel      = access_en & (access_addr[ADDR_WIDTH-1:BLOCK_SIZE_WIDTH] >= `BUS_BASE_ADDR) ;
assign access_illegal = access_en ? (access_addr[ADDR_WIDTH-1:BLOCK_SIZE_WIDTH] < `DTCM_BASE_TAG): 1'b0;

`ifdef DTCM_ASYNC_READ
// ============================================
// 异步读模式：DTCM 读数据组合输出，单周期完成
// ============================================

assign mem_access_ready = bus_sel ? bus_tran_done : 1'b1; // DTCM 总是 ready
assign rd_mem_data      = dtcm_sel ? rd_dtcm_data : rd_bus_data;

assign exception_code = access_illegal ? (access_wr ? 4'd7 : 4'd5) : {DATA_WIDTH-1{1'b1}};
assign exception_val = access_addr;

// 符号扩展
always_comb begin
    if (access_en) begin
        case (rd_mem_func3)
            `INST_LB : begin
                case (access_addr[1:0])
                    2'b00:wr_reg_data = {{24{rd_mem_data[7]}},rd_mem_data[7:0]};
                    2'b01:wr_reg_data = {{24{rd_mem_data[15]}},rd_mem_data[15:8]};
                    2'b10:wr_reg_data = {{24{rd_mem_data[23]}},rd_mem_data[23:16]};
                    2'b11:wr_reg_data = {{24{rd_mem_data[31]}},rd_mem_data[31:24]};
                    default:wr_reg_data = {{24{rd_mem_data[7]}},rd_mem_data[7:0]};
                endcase
            end
            `INST_LH : begin
                case (access_addr[1])
                    1'b0:wr_reg_data = {{16{rd_mem_data[15]}},rd_mem_data[15:0]};
                    1'b1:wr_reg_data = {{16{rd_mem_data[31]}},rd_mem_data[31:16]};
                    default:wr_reg_data = {{16{rd_mem_data[15]}},rd_mem_data[15:0]};
                endcase
            end
            `INST_LW : begin
                wr_reg_data = rd_mem_data;
            end
            `INST_LBU : begin
                case (access_addr[1:0])
                    2'b00:wr_reg_data = {24'h0,rd_mem_data[7:0]};
                    2'b01:wr_reg_data = {24'h0,rd_mem_data[15:8]};
                    2'b10:wr_reg_data = {24'h0,rd_mem_data[23:16]};
                    2'b11:wr_reg_data = {24'h0,rd_mem_data[31:24]};
                    default:wr_reg_data = {24'h0,rd_mem_data[7:0]};
                endcase
            end
            `INST_LHU : begin
                case (access_addr[1])
                    1'b0:wr_reg_data = {16'h0,rd_mem_data[15:0]};
                    1'b1:wr_reg_data = {16'h0,rd_mem_data[31:16]};
                    default:wr_reg_data = {16'h0,rd_mem_data[15:0]};
                endcase
            end
            default : wr_reg_data = wr_reg_data_from_ex_mem;
        endcase
    end else begin
        wr_reg_data = wr_reg_data_from_ex_mem;
    end
end

`else
// ============================================
// 同步读模式：DTCM 读数据延迟 1 拍（BRAM 行为）
// 需要 dtcm_data_valid 状态机追踪地址/数据周期
// ============================================

// DTCM 同步读状态机：
// dtcm_data_valid=0：地址周期（DTCM 正在采样地址），数据尚不可用
// dtcm_data_valid=1：数据周期（DTCM 读出有效），数据可用
// 只有 DTCM load 才进入状态机；DTCM store 直接完成（不读数据）
// 注意：dtcm_rd_phase 不受 stall 影响，因为 DTCM 采样地址不受流水线 stall 控制
logic dtcm_data_valid;
logic dtcm_load; // DTCM load 标志

assign dtcm_load = dtcm_sel & ~access_wr; // DTCM 读访问

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        dtcm_data_valid <= 1'b0;
    else begin
        // 状态转换：
        // 0→1：DTCM load 进入地址周期，下一拍 BRAM 输出数据
        // 1→0：数据周期完成（流水线推进），回到空闲
        if (dtcm_data_valid) begin
            dtcm_data_valid <= 1'b0;
        end else begin
            // 地址周期：如果有 DTCM load，推进到数据周期
            dtcm_data_valid <= dtcm_load;
        end
    end
end

// mem_access_ready：
// - 总线访问：等待 bus_tran_done
// - DTCM store：立即完成
// - DTCM load：等待数据周期（dtcm_data_valid）
assign mem_access_ready = bus_sel ? bus_tran_done :
                          (dtcm_sel & ~access_wr) ? dtcm_data_valid : 1'b1;

// 读数据选择：数据周期用 DTCM 读出，地址周期无有效数据
assign rd_mem_data = dtcm_sel ? rd_dtcm_data : rd_bus_data;

assign exception_code = access_illegal ? (access_wr ? 4'd7 : 4'd5) : {DATA_WIDTH-1{1'b1}};
assign exception_val = access_addr;

// 符号扩展：只有数据周期（dtcm_data_valid）时才做扩展，否则透传 EX_MEM 数据
always_comb begin
    if (access_en) begin
        case (rd_mem_func3)
            `INST_LB : begin
                case (access_addr[1:0])
                    2'b00:wr_reg_data = {{24{rd_mem_data[7]}},rd_mem_data[7:0]};
                    2'b01:wr_reg_data = {{24{rd_mem_data[15]}},rd_mem_data[15:8]};
                    2'b10:wr_reg_data = {{24{rd_mem_data[23]}},rd_mem_data[23:16]};
                    2'b11:wr_reg_data = {{24{rd_mem_data[31]}},rd_mem_data[31:24]};
                    default:wr_reg_data = {{24{rd_mem_data[7]}},rd_mem_data[7:0]};
                endcase
            end
            `INST_LH : begin
                case (access_addr[1])
                    1'b0:wr_reg_data = {{16{rd_mem_data[15]}},rd_mem_data[15:0]};
                    1'b1:wr_reg_data = {{16{rd_mem_data[31]}},rd_mem_data[31:16]};
                    default:wr_reg_data = {{16{rd_mem_data[15]}},rd_mem_data[15:0]};
                endcase
            end
            `INST_LW : begin
                wr_reg_data = rd_mem_data;
            end
            `INST_LBU : begin
                case (access_addr[1:0])
                    2'b00:wr_reg_data = {24'h0,rd_mem_data[7:0]};
                    2'b01:wr_reg_data = {24'h0,rd_mem_data[15:8]};
                    2'b10:wr_reg_data = {24'h0,rd_mem_data[23:16]};
                    2'b11:wr_reg_data = {24'h0,rd_mem_data[31:24]};
                    default:wr_reg_data = {24'h0,rd_mem_data[7:0]};
                endcase
            end
            `INST_LHU : begin
                case (access_addr[1])
                    1'b0:wr_reg_data = {16'h0,rd_mem_data[15:0]};
                    1'b1:wr_reg_data = {16'h0,rd_mem_data[31:16]};
                    default:wr_reg_data = {16'h0,rd_mem_data[15:0]};
                endcase
            end
            default : wr_reg_data = wr_reg_data_from_ex_mem;
        endcase
    end else begin
        wr_reg_data = wr_reg_data_from_ex_mem;
    end
end

`endif // DTCM_ASYNC_READ

endmodule
