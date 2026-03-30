`include "./../SoC_Config.sv"
`timescale 1ns / 1ps
module APB_Master #(
    parameter ADDR_WIDTH = `ADDR_WIDTH,
    parameter DATA_WIDTH = `DATA_WIDTH,
    parameter ALIGN_BYTES = `ALIGN_BYTES
)(
    //clk and rst
    input   logic                       i_sys_clk,// 时钟信号
    input   logic                       i_rst_n,// 复位信号，低电平有效
    // connect User
    // 外部输入的User信号和i_sys_clk同源，不必做异步处理
    input   logic                       i_en,
    input   logic                       i_write,
    input   logic   [ADDR_WIDTH-1:0]    i_addr,
    input   logic   [DATA_WIDTH-1:0]    i_wdata,
    input   logic   [ALIGN_BYTES-1:0]   i_wmask,
    output  logic   [DATA_WIDTH-1:0]    o_rdata,
    output  logic                       o_tran_done,
    // connect APB Slave
    output  logic   [ADDR_WIDTH-1:0]    o_PADDR,// 地址总线
    output  logic                       o_PSEL,// 选择信号
    output  logic                       o_PENABLE,// 使能信号
    output  logic                       o_PWRITE,// 写信号
    output  logic   [ALIGN_BYTES-1:0]   o_PSTRB, // 写使能信号
    output  logic   [DATA_WIDTH-1:0]    o_PWDATA,// 写数据总线
    input   logic   [DATA_WIDTH-1:0]    i_PRDATA,// 读数据总线
    input   logic                       i_PREADY,// 准备就绪信号
    input   logic                       i_PSLVERR// 错误信号
);

/********************localparam*********************/

localparam  IDLE            =  5'b00001;
localparam  STA_WR          =  5'b00010;
localparam  STA_RD          =  5'b00100;
localparam  STA_ENABLE_WAIT =  5'b01000;
localparam  STA_DONE        =  5'b10000;
/********************state*********************/
logic    [4:0]   current_state  ;
logic    [4:0]   next_state  ;

/********************reg*********************/
//connect to APB Slave
logic   [ADDR_WIDTH-1:0]    PADDR      ;
logic   [DATA_WIDTH-1:0]    PWDATA     ;
logic                       PWRITE     ;
logic                       PSEL       ;
logic                       PENABLE    ;
logic   [ALIGN_BYTES-1:0]   PSTRB      ;
//connect to User
logic                       tran_done  ;
logic   [DATA_WIDTH-1:0]    PRDATA     ;

always_ff @(posedge i_sys_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        current_state  <= #1 IDLE ;
    end
    else begin
        current_state  <= #1 next_state ;
    end
end 

always_comb begin
    next_state = IDLE;
    if(i_rst_n) begin
        case(current_state)
            IDLE:
                begin
                    if(i_write & i_en)
                        next_state = STA_WR ;
                    else if(!i_write & i_en)
                        next_state = STA_RD ;
                    else
                        next_state = IDLE;
                end
            STA_WR:
                begin
                    next_state = STA_ENABLE_WAIT;
                end
            STA_RD:
                begin
                    next_state = STA_ENABLE_WAIT;
                end
            STA_ENABLE_WAIT:
                begin
                    if(i_PREADY)
                        next_state = IDLE;
                    else
                        next_state = STA_ENABLE_WAIT;
                end
            // STA_DONE:
            //     begin
            //         next_state = IDLE;
            //     end
            default:
                begin
                    next_state = IDLE;
                end
        endcase
    end
end

always_comb begin
    PADDR     = 'h0;
    PWDATA    = 'h0;
    PWRITE    = 1'b0;
    PSEL      = 1'b0;
    PENABLE   = 1'b0;
    PSTRB     = 'h0;
    tran_done = 1'b0;
    PRDATA    = 'h0;
    if (i_rst_n) begin
        case(current_state)
            STA_WR:
                begin
                    PADDR     = i_addr   ;
                    PWDATA    = i_wdata  ;
                    PSTRB     = i_wmask  ;
                    PWRITE    = 1'b1     ;
                    PSEL      = 1'b1     ;
                    PENABLE   = 1'b0     ;
                end
            STA_RD:
                begin
                    PADDR     = i_addr   ;
                    //PWDATA  = i_wdata  ;
                    PWRITE    = 1'b0     ;
                    PSEL      = 1'b1     ;
                    PENABLE   = 1'b0     ;
                end
            STA_ENABLE_WAIT:
                begin
                    PADDR     = i_addr;     // 保持地址稳定
                    PWDATA    = i_write ? i_wdata : 'h0;    // 写事务保持数据
                    PSTRB     = i_write ? i_wmask : 'h0;
                    PWRITE    = i_write ;    // 保持读写方向
                    PSEL      = 1'b1;       // PSEL全程保持高
                    PENABLE   = 1'b1;       // ENABLE阶段置位
                    PRDATA    = i_PRDATA;   // 提前锁存读数据（不影响）
                    tran_done = i_PREADY;
                end
            // STA_DONE:
            //     begin
            //         tran_done = 1'b1     ;
            //         PRDATA    = i_PRDATA ;
            //         PSEL      = 1'b0;
            //         PENABLE   = 1'b0;
            //     end
            default:;
        endcase
    end
end

/********************comb*********************/
//connect to APB Slave
assign  o_PADDR     =   PADDR    ;
assign  o_PSEL      =   PSEL     ;
assign  o_PENABLE   =   PENABLE  ;
assign  o_PWRITE    =   PWRITE   ;
assign  o_PSTRB     =   PSTRB    ;
assign  o_PWDATA    =   PWDATA   ;


// assign  o_PSTRB     =  w_strobe ;
//connect to User
assign  o_tran_done =   tran_done ;
assign  o_rdata     =   PRDATA    ;

endmodule

