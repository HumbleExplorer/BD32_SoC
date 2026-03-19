`include "./../SoC_Config.sv"
`include "./../RV32_inst_Define.sv"

module IF_ID #(
    parameter ADDR_WIDTH = `ADDR_WIDTH,
    parameter DATA_WIDTH = `DATA_WIDTH
)(
    input   logic                       clk,
    input   logic                       rst_n,
    //from ctrl
    input   logic                       stall,
    input   logic                       flush,
    //from if
    input   logic   [ADDR_WIDTH-1:0]    inst_addr_i,
    input   logic   [DATA_WIDTH-1:0]    inst_i,
    //to id
    output  logic   [ADDR_WIDTH-1:0]    inst_addr_o,
    output  logic   [DATA_WIDTH-1:0]    inst_o
);

always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        inst_addr_o     <= {`BOOT_BASE_ADDR,16'h0};
        inst_o          <= `INST_NOP;
    end else if(flush) begin
        inst_addr_o     <= {`BOOT_BASE_ADDR,16'h0};
        inst_o          <= `INST_NOP;
    end else if (!stall) begin//指令地址无需清零
        inst_addr_o     <= inst_addr_i;
        inst_o          <= inst_i;
        // inst_o          <= inst_i == {DATA_WIDTH{1'bx}} ? `INST_NOP : inst_i;//冗余设计
    end
end
endmodule


