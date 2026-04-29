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
    input   logic                       i_transfer,
    input   logic                       i_write,
    input   logic   [ADDR_WIDTH-1:0]    i_addr,
    input   logic   [DATA_WIDTH-1:0]    i_wdata,
    input   logic   [ALIGN_BYTES-1:0]   i_wmask,
    output  logic   [DATA_WIDTH-1:0]    o_rdata,
    output  logic                       o_tran_done,
    // connect APB Slave
    (* mark_debug = "true" *)output  logic   [ADDR_WIDTH-1:0]    o_PADDR,// 地址总线
    (* mark_debug = "true" *)output  logic                       o_PSEL,// 选择信号
    (* mark_debug = "true" *)output  logic                       o_PENABLE,// 使能信号
    (* mark_debug = "true" *)output  logic                       o_PWRITE,// 写信号
    (* mark_debug = "true" *)output  logic   [ALIGN_BYTES-1:0]   o_PSTRB, // 写使能信号
    (* mark_debug = "true" *)output  logic   [DATA_WIDTH-1:0]    o_PWDATA,// 写数据总线
    (* mark_debug = "true" *)input   logic   [DATA_WIDTH-1:0]    i_PRDATA,// 读数据总线
    (* mark_debug = "true" *)input   logic                       i_PREADY,// 准备就绪信号
    (* mark_debug = "true" *)input   logic                       i_PSLVERR// 错误信号
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
logic                       tran_done  ;
logic   [DATA_WIDTH-1:0]    PRDATA     ;


always_ff @(posedge i_sys_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        current_state     <= #1 IDLE;
    end
    else begin
        current_state     <= #1 next_state;
    end
end 

// =============================================================================
// 根据 APB_ACCESS_MIN_STAGES 宏值生成不同的状态转移逻辑
// =============================================================================
generate
    if (`APB_ACCESS_MIN_STAGES == 1) begin : gen_fsm_min1
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
    end
    else begin : gen_fsm_min2
        // APB_ACCESS_MIN_STAGES >= 2：ACCESS至少停留2拍后进入DONE
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
    end
endgenerate

// =============================================================================
// 根据 APB_ACCESS_MIN_STAGES 宏值生成不同的输出逻辑
// =============================================================================
generate
    if (`APB_ACCESS_MIN_STAGES == 1) begin : gen_out_min1
        always_comb begin
            PADDR     = 'h0;
            PWDATA    = 'h0;
            PWRITE    = 1'b0;
            PSEL      = 1'b0;
            PENABLE   = 1'b0;
            PSTRB     = 'h0;
            PRDATA    = 'h0;
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
    end
    else begin : gen_out_min2
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
endgenerate

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

