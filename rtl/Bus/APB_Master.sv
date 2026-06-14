`include "./../SoC_Config.sv"
timeunit 1ns;
timeprecision 1ps;
module APB_Master #(
    parameter ADDR_WIDTH = `ADDR_WIDTH,
    parameter DATA_WIDTH = `DATA_WIDTH,
    parameter ALIGN_BYTES = `ALIGN_BYTES
)(
    //clk and rst
    input   logic                       i_sys_clk,// 时钟信号
    input   logic                       i_rst_n,// 复位信号，低电平有效
    // connect User
    input   logic                       i_transfer,
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
typedef enum logic [2:0] { 
    IDLE    = 3'b001,
    SETUP   = 3'b010,
    ACCESS  = 3'b100
} apb_state_e;
/********************state*********************/
apb_state_e current_state;
apb_state_e next_state;

/********************reg*********************/
//connect to APB Slave
logic   [ADDR_WIDTH-1:0]    PADDR      ;
logic   [DATA_WIDTH-1:0]    PWDATA     ;
logic                       PWRITE     ;
logic                       PSEL       ;
logic                       PENABLE    ;
logic   [ALIGN_BYTES-1:0]   PSTRB      ;

//connect to User
logic   [DATA_WIDTH-1:0]    PRDATA     ;
logic                       tran_done  ;



always_ff @(posedge i_sys_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        current_state     <= #1 IDLE;
    end
    else begin
        current_state     <= #1 next_state;
    end
end 


`ifndef APB_ACCESS_DELAYED_DONE
        // 传统APB：ACCESS见PREADY即可离开（backward compatible）
        
        always_comb begin
            next_state = IDLE;
            if(i_rst_n) begin
                case(current_state)
                    IDLE: begin
                        if(i_transfer)
                            next_state = SETUP;
                        else
                            next_state = IDLE;
                    end
                    SETUP: begin
                        next_state = ACCESS;
                    end
                    ACCESS: begin
                        if(i_PREADY)
                            next_state = i_transfer ? SETUP : IDLE;
                        else
                            next_state = ACCESS;
                    end
                    default: begin
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
            PRDATA    = 'h0;
            tran_done = 1'b0;
            if (i_rst_n) begin
                case(current_state)
                    SETUP:
                        begin
                            PADDR     = i_addr   ;
                            PWDATA    = i_wdata  ;
                            PSTRB     = i_wmask  ;
                            PWRITE    = i_write  ;
                            PSEL      = 1'b1     ;
                            PENABLE   = 1'b0     ;
                        end
                    ACCESS:
                        begin
                            PADDR     = i_addr;
                            PWDATA    = i_write ? i_wdata : 'h0;
                            PSTRB     = i_write ? i_wmask : 'h0;
                            PWRITE    = i_write ;
                            PSEL      = 1'b1;
                            PENABLE   = 1'b1;
                            PRDATA    = i_PRDATA;
                            tran_done = i_PREADY;   // PREADY时即完成
                        end
                    default:;
                endcase
            end
        end
`else
        always_comb begin
            next_state = IDLE;
            if(i_rst_n) begin
                case(current_state)
                    IDLE: begin
                        if(i_transfer)
                            next_state = SETUP;
                        else
                            next_state = IDLE;
                    end
                    SETUP: begin
                        next_state = ACCESS;
                    end
                    ACCESS: begin
                        if(i_PREADY)
                            next_state = IDLE;
                        else
                            next_state = ACCESS;
                    end
                    default: begin
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
            if (i_rst_n) begin
                case(current_state)
                    SETUP:
                        begin
                            PADDR     = i_addr   ;
                            PWDATA    = i_wdata  ;
                            PSTRB     = i_wmask  ;
                            PWRITE    = i_write  ;
                            PSEL      = 1'b1     ;
                            PENABLE   = 1'b0     ;
                        end
                    ACCESS:
                        begin
                            PADDR     = i_addr;
                            PWDATA    = i_write ? i_wdata : 'h0;
                            PSTRB     = i_write ? i_wmask : 'h0;
                            PWRITE    = i_write ;
                            PSEL      = 1'b1;
                            PENABLE   = 1'b1;
                        end
                    default:;
                endcase
            end
        end
    end

    always_ff @(posedge i_sys_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            tran_done <= 1'b0;
            PRDATA    <= 'h0;
        end else begin
            case(current_state)
                ACCESS: begin
                    if(i_PREADY) begin
                        PRDATA    <= i_PRDATA;
                        tran_done <= 1'b1;
                    end else begin
                        tran_done <= 1'b0;
                    end
                end
                default: begin
                    tran_done <= 1'b0;
                end
            endcase
        end
    end
`endif



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

