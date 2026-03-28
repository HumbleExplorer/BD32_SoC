`include "./../SoC_Config.sv"
`include "./../RV32_inst_Define.sv"
module Mem_Access #(//模块内的mem指所有用到load、store的部分
    parameter ADDR_WIDTH = `ADDR_WIDTH,
    parameter DATA_WIDTH = `DATA_WIDTH,
    localparam BLOCK_SIZE_WIDTH = ADDR_WIDTH - `DEVICE_TAG_WIDTH
)(
    input   logic   [ADDR_WIDTH-1:0]    access_addr,
    input   logic                       access_en,
    input   logic                       access_wr,
    input   logic                       bus_tran_done,
    input   logic   [DATA_WIDTH-1:0]    rd_dtcm_data,
    input   logic   [DATA_WIDTH-1:0]    rd_clint_data,
    input   logic   [DATA_WIDTH-1:0]    rd_plic_data,
    input   logic   [DATA_WIDTH-1:0]    rd_bus_data,
    input   logic   [2:0]               rd_mem_func3,
    input   logic   [DATA_WIDTH-1:0]    wr_reg_data_from_ex_mem,
    //to dtcm/clint/plic/bus
    output  logic                       dtcm_sel,
    output  logic                       bus_sel,
    output  logic                       clint_sel,
    output  logic                       plic_sel,
    //to crtl
    output  logic                       mem_access_ready,
    output  logic   [DATA_WIDTH-2:0]    exception_code,
    output  logic   [DATA_WIDTH-1:0]    exception_val,
    //to MEM/WB
    output  logic   [DATA_WIDTH-1:0]    wr_reg_data
);

logic [DATA_WIDTH-1:0] wr_reg_data_from_mem_periph;
logic [DATA_WIDTH-1:0] rd_mem_data;
logic direct_sel;//此处的direct指可以单周期读写，不经过总线读写的，所以没有ready
logic [DATA_WIDTH-1:0] rd_direct_data;
logic                  access_illegal;

assign dtcm_sel     = access_en & (access_addr[ADDR_WIDTH-1:BLOCK_SIZE_WIDTH] == `DTCM_BASE_ADDR) ;
assign clint_sel    = access_en & (access_addr[ADDR_WIDTH-1:BLOCK_SIZE_WIDTH] == `CLINT_BASE_ADDR);
assign plic_sel     = access_en & (access_addr[ADDR_WIDTH-1:BLOCK_SIZE_WIDTH] == `PLIC_BASE_ADDR);
assign bus_sel      = access_en & (access_addr[ADDR_WIDTH-1:BLOCK_SIZE_WIDTH] >= `BUS_BASE_ADDR);
assign direct_sel   = dtcm_sel || clint_sel || plic_sel;
assign rd_direct_data = plic_sel ? rd_plic_data : (clint_sel ? rd_clint_data : (dtcm_sel ? rd_dtcm_data : 'h0));
// assign mem_access_ready = access_en ? (direct_sel ? 1'b1 : (bus_sel ? bus_tran_done : 1'b0)): 1'b1;
assign mem_access_ready = bus_sel ? bus_tran_done : 1'b1;
// assign rd_mem_en = access_en & ~access_wr;
// assign wr_mem_en = access_en & access_wr;
assign rd_mem_data = direct_sel ? rd_direct_data : (bus_sel ? rd_bus_data : 'h0);
assign access_illegal = access_en ? (access_addr[ADDR_WIDTH-1:BLOCK_SIZE_WIDTH] < `DTCM_BASE_ADDR): 1'b0;//还可以再加上总线传来的错误信息
// assign exception_code = access_illegal ? (rd_mem_en ? 4'd5 : wr_mem_en ? 4'd7 : {DATA_WIDTH-1{1'b1}}): {DATA_WIDTH-1{1'b1}};
assign exception_code = access_illegal ? (access_wr ? 4'd7 : 4'd5) : {DATA_WIDTH-1{1'b1}};
assign exception_val = access_addr;
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
        endcase
    end else begin
        wr_reg_data = wr_reg_data_from_ex_mem;
    end
end
endmodule

