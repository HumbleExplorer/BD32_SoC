`include "../../SoC_Config.sv"
timeunit 1ns;
timeprecision 1ps;
module apb_uart #(
    parameter ADDR_WIDTH = `ADDR_WIDTH,
    parameter DATA_WIDTH = `DATA_WIDTH,
    parameter ALIGN_BYTES = `ALIGN_BYTES,
    parameter ALIGN_WIDTH = `ALIGN_WIDTH
)(
    // APB总线接口（4字节对齐）
    input   logic                       PCLK,
    input   logic                       PRESETn,
    input   logic   [ADDR_WIDTH-1:0]    PADDR,
    input   logic                       PSEL,
    input   logic                       PENABLE,
    input   logic                       PWRITE,
    input   logic   [DATA_WIDTH-1:0]    PWDATA,
    output  logic   [DATA_WIDTH-1:0]    PRDATA,
    output  logic                       PREADY,
    output  logic                       PSLVERR,
    output  logic                       irq_o,
    input   logic                       uart_rx_i,
    output  logic                       uart_tx_o,
    output  logic                       itcm_download_en_o,
    output  logic   [ADDR_WIDTH-1:0]    itcm_download_addr_o,
    output  logic   [DATA_WIDTH-1:0]    itcm_download_data_o,
    output  logic                       dtcm_download_en_o,
    output  logic   [ADDR_WIDTH-1:0]    dtcm_download_addr_o,
    output  logic   [DATA_WIDTH-1:0]    dtcm_download_data_o
);

localparam DLAB_BIT       = 7;// LCR[7]：除数锁存访问位（顶层仅需此位）
localparam FCR_CLR_RX     = 1;// FCR[1]：清接收FIFO
localparam FCR_CLR_TX     = 2;// FCR[2]：清发送FIFO
// 中断标识定义（IIR）- 严格遵循16550手册
localparam IIR_NO_INT     = 8'hC1;// 无中断 (FIFO Enabled)
localparam IIR_RLS_INT    = 8'h06;// 接收线状态中断 (最高优先级)
localparam IIR_RDA_INT    = 8'h04;// 接收数据就绪
localparam IIR_TOUT_INT   = 8'h0C;// 接收超时
localparam IIR_THRE_INT   = 8'h02;// 发送保持寄存器空
localparam IIR_MSR_INT    = 8'h00;// 调制解调器状态

typedef enum logic[3:0] {
    REG_SEL_0 = 4'b0000,// 0x00: RBR/THR/DLL (受DLAB控制)
    REG_SEL_1 = 4'b0001,// 0x04: IER/DLM     (受DLAB控制)
    REG_SEL_2 = 4'b0010,// 0x08: IIR (读) / FCR (写)
    REG_SEL_3 = 4'b0011,// 0x0C: LCR
    REG_SEL_4 = 4'b0100,// 0x10: MCR
    REG_SEL_5 = 4'b0101,// 0x14: LSR (只读)
    REG_SEL_6 = 4'b0110,// 0x18: MSR (只读)
    REG_SEL_7 = 4'b0111,// 0x1C: DBG_EN (只写)
    REG_SEL_8 = 4'b1000,// 0x20: DBG_DONE (只读)
    REG_SEL_9 = 4'b1001 // 0x24: FCW[31:0] (读写，NCO 频率控制字)
} uart_reg_sel_e;

logic [3:0] reg_sel;

// 16550 核心寄存器（divisor 保留兼容，NCO 不使用）
logic[15:0]    divisor;     // 除数寄存器 {DLM[15:8], DLL[7:0]}
logic[3:0]     ier;         // 中断使能寄存器
logic[7:0]     iir;         // 中断标识寄存器（只读）
logic[7:0]     fcr;         // FIFO控制寄存器（只写）
logic[7:0]     lcr;         // 线控制寄存器（8位完整，直接传给子模块）
logic[7:0]     mcr;         // 调制解调器控制
(* mark_debug = "true" *) logic[7:0]     lsr;         // 线状态寄存器（只读）
logic[7:0]     msr;         // 调制解调器状态（只读）
(* mark_debug = "true" *) logic[31:0]    fcw;     // NCO 频率控制字

// 子模块接口信号
logic[7:0]     rx_data_out;
logic          rx_data_valid;
logic[3:0]     rx_err;
logic[7:0]     tx_data_in;
logic          tx_start;
logic          tx_busy;

// FIFO 接口
logic           rx_fifo_wr_en;
logic           rx_fifo_rd_en;
logic           tx_fifo_wr_en;
logic           tx_fifo_rd_en;
logic   [7:0]   rx_fifo_rdata;
logic   [7:0]   tx_fifo_wdata;
logic           rx_fifo_rd_empty;
logic           tx_fifo_rd_empty;
logic           rx_fifo_wr_full;
logic           tx_fifo_wr_full;
logic   [4:0]   rx_fifo_cnt;
logic   [5:0]   timeout_cnt;
logic           timeout;
logic           reg_rd_en, reg_wr_en;
(* mark_debug = "true" *) logic           sample_pulse;   // NCO 采样使能脉冲
logic   [3:0]   tx_sample_cnt;      // ÷16 计数，生成 1x 位时钟
logic           tx_uart_pulse; // 1x 位时钟采样脉冲
(* mark_debug = "true" *) logic           download_en;
(* mark_debug = "true" *) logic           download_done;


assign  reg_sel   = PADDR[5:2];
assign  reg_rd_en = PSEL & !PWRITE & PENABLE;
assign  reg_wr_en = PSEL & PWRITE & PENABLE;
assign  timeout   = timeout_cnt == 6'd63;
assign  tx_uart_pulse = (tx_sample_cnt == 4'd15) && sample_pulse;

// ==================== 1. 寄存器写逻辑 ====================
always_ff @(posedge PCLK or negedge PRESETn) begin
    if (!PRESETn) begin
        divisor     <= #1 16'd0;
        ier         <= #1 4'd0;
        fcr         <= #1 8'hC0;
        lcr         <= #1 8'h03;
        mcr         <= #1 8'd0;
        fcw         <= #1 '0;
        download_en <= #1 1'b0;
    end else begin
        if (reg_wr_en) begin
            case (uart_reg_sel_e'(reg_sel))
                REG_SEL_0: begin
                    if (lcr[DLAB_BIT]) divisor[7:0] <= #1 PWDATA[7:0];
                end
                REG_SEL_1: begin
                    if (lcr[DLAB_BIT]) divisor[15:8] <= #1 PWDATA[7:0];
                    else ier <= #1 PWDATA[3:0];
                end
                REG_SEL_2: begin
                    fcr <= #1 PWDATA[7:0];
                end
                REG_SEL_3: begin
                    lcr <= #1 PWDATA[6] ? (PWDATA[7:0] & 8'h7F) : PWDATA[7:0];
                end
                REG_SEL_4: mcr <= #1 PWDATA[7:0];
                REG_SEL_7: download_en <= #1 PWDATA[0];
                REG_SEL_9: fcw <= #1 PWDATA[31:0];  // FCW
                default: ;
            endcase
        end
        if (fcr[FCR_CLR_RX])
            fcr[FCR_CLR_RX] <= #1 1'b0;
        if (fcr[FCR_CLR_TX])
            fcr[FCR_CLR_TX] <= #1 1'b0;
    end
end

// ==================== FIFO 读写使能 ====================
assign  tx_fifo_rd_en  = tx_uart_pulse && ~tx_fifo_rd_empty & ~tx_busy;
assign  tx_fifo_wr_en  = reg_wr_en && uart_reg_sel_e'(reg_sel) == REG_SEL_0 && ~lcr[DLAB_BIT]
                         && ~tx_fifo_wr_full;
assign  tx_fifo_wdata  = PWDATA[7:0];
assign  rx_fifo_wr_en  = rx_data_valid & ~rx_fifo_wr_full;
assign  rx_fifo_rd_en  = ((reg_rd_en && uart_reg_sel_e'(reg_sel) == REG_SEL_0 && ~lcr[DLAB_BIT])
                          || (download_en && ~download_done))
                          && ~rx_fifo_rd_empty;

// ==================== 2. 寄存器读逻辑 ====================
always_comb begin
    PRDATA = {DATA_WIDTH{1'b0}};
    if (reg_rd_en) begin
        case (uart_reg_sel_e'(reg_sel))
            REG_SEL_0: begin
                if (lcr[DLAB_BIT]) PRDATA[7:0] = divisor[7:0];
                else                PRDATA[7:0] = rx_fifo_rdata;
            end
            REG_SEL_1: begin
                if (lcr[DLAB_BIT]) PRDATA[7:0] = divisor[15:8];
                else                PRDATA[7:0] = {4'd0, ier};
            end
            REG_SEL_2: PRDATA[7:0] = iir;
            REG_SEL_3: PRDATA[7:0] = lcr;
            REG_SEL_4: PRDATA[7:0] = mcr;
            REG_SEL_5: PRDATA[7:0] = lsr;
            REG_SEL_6: PRDATA[7:0] = msr;
            REG_SEL_8: PRDATA[1:0] = {download_en, download_done};
            REG_SEL_9: PRDATA[31:0] = fcw;
            default: ;
        endcase
    end
end

// ==================== 3. LSR 状态更新 ====================
always_ff @(posedge PCLK or negedge PRESETn) begin
    if (!PRESETn) begin
        lsr <= #1 8'h60;
    end else begin
        lsr[0] <= #1 ~rx_fifo_rd_empty;
        lsr[1] <= #1 rx_err[0] ? 1'b1 : (reg_rd_en && reg_sel == REG_SEL_5) ? 1'b0 : lsr[1];
        lsr[2] <= #1 rx_err[1] ? 1'b1 : (reg_rd_en && reg_sel == REG_SEL_5) ? 1'b0 : lsr[2];
        lsr[3] <= #1 rx_err[2] ? 1'b1 : (reg_rd_en && reg_sel == REG_SEL_5) ? 1'b0 : lsr[3];
        lsr[4] <= #1 rx_err[3] ? 1'b1 : (reg_rd_en && reg_sel == REG_SEL_5) ? 1'b0 : lsr[4];
        lsr[5] <= #1 tx_fifo_rd_empty;
        lsr[6] <= #1 (tx_fifo_rd_empty && ~tx_busy);
        lsr[7] <= #1 (lsr[1] | lsr[2] | lsr[3] | lsr[4]);
    end
end

// ==================== 4. 中断逻辑 ====================
always_ff @(posedge PCLK or negedge PRESETn) begin
    if (!PRESETn) begin
        timeout_cnt <= #1 6'd0;
        irq_o       <= #1 1'b0;
        iir         <= #1 IIR_NO_INT;
    end else begin
        if (rx_fifo_rd_empty || rx_fifo_wr_en || rx_fifo_rd_en)
            timeout_cnt <= #1 6'd0;
        else if (timeout)
            timeout_cnt <= #1 6'd0;
        else
            timeout_cnt <= #1 timeout_cnt + 1'b1;

        if (ier[2] && (lsr[1] | lsr[2] | lsr[3] | lsr[4])) begin
            irq_o <= #1 1'b1; iir <= #1 IIR_RLS_INT;
        end else if (ier[0] && rx_fifo_cnt >= get_trigger()) begin
            irq_o <= #1 1'b1; iir <= #1 timeout ? IIR_TOUT_INT : IIR_RDA_INT;
        end else if (ier[1] && tx_fifo_rd_empty) begin
            irq_o <= #1 1'b1; iir <= #1 IIR_THRE_INT;
        end else if (ier[3] && (msr[0] | msr[1] | msr[2] | msr[3])) begin
            irq_o <= #1 1'b1; iir <= #1 IIR_MSR_INT;
        end else begin
            irq_o <= #1 1'b0; iir <= #1 IIR_NO_INT;
        end

        if (reg_rd_en) begin
            if (reg_sel == REG_SEL_2 && (iir == IIR_THRE_INT)) begin
                irq_o <= #1 1'b0; iir <= #1 IIR_NO_INT;
            end else if (reg_sel == REG_SEL_5 && (iir == IIR_RLS_INT)) begin
                irq_o <= #1 1'b0; iir <= #1 IIR_NO_INT;
            end else if (reg_sel == REG_SEL_6 && (iir == IIR_MSR_INT)) begin
                irq_o <= #1 1'b0; iir <= #1 IIR_NO_INT;
            end else if (reg_sel == REG_SEL_0 && !lcr[DLAB_BIT]
                       && (iir[3:0] == IIR_RDA_INT[3:0] || iir[3:0] == IIR_TOUT_INT[3:0])) begin
                irq_o <= #1 1'b0; iir <= #1 IIR_NO_INT;
            end
        end
    end
end

function automatic logic[3:0] get_trigger();
    case (fcr[7:6])
        2'b00: return 4'd1;
        2'b01: return 4'd4;
        2'b10: return 4'd8;
        2'b11: return 4'd14;
        default: return 4'd1;
    endcase
endfunction

// ÷16 计数：sample_pulse 脉冲下生成 1x 位时钟
always_ff @(posedge PCLK or negedge PRESETn) begin
    if(!PRESETn)
        tx_sample_cnt <= #1 4'd0;
    else if(sample_pulse) begin
        tx_sample_cnt <= #1 (tx_sample_cnt == 4'd15) ? 4'd0 : tx_sample_cnt + 1'b1;
    end
end

// ==================== 5. 子模块例化 ====================
nco_baudgen #(.FCW_WIDTH(32)) u_nco (
    .clk           (PCLK),
    .rst_n         (PRESETn),
    .fcw           (fcw),
    .sample_pulse  (sample_pulse)
);

uart_rx u_uart_rx(
    .clk                (PCLK),
    .sample_pulse       (sample_pulse),
    .rst_n              (PRESETn),
    .rx_i               (uart_rx_i),
    .lcr                (lcr),
    .rx_fifo_wr_full    (rx_fifo_wr_full),
    .rx_o               (rx_data_out),
    .rx_valid_o         (rx_data_valid),
    .rx_err             (rx_err)
);

uart_tx u_uart_tx(
    .clk                (PCLK),
    .rst_n              (PRESETn),
    .tx_uart_pulse      (tx_uart_pulse),
    .tx_i               (tx_data_in),
    .tx_start           (tx_start),
    .lcr                (lcr),
    .tx_o               (uart_tx_o),
    .tx_busy            (tx_busy)
);

sync_fifo #(.DEPTH(16), .DATA_WIDTH(8)) rx_fifo_inst(
    .clk        (PCLK),
    .rst_n      (PRESETn),
    .wr_en      (rx_fifo_wr_en),
    .wr_data    (rx_data_out),
    .rd_en      (rx_fifo_rd_en),
    .rd_data    (rx_fifo_rdata),
    .full       (rx_fifo_wr_full),
    .empty      (rx_fifo_rd_empty),
    .count      (rx_fifo_cnt)
);

sync_fifo #(.DEPTH(16), .DATA_WIDTH(8)) tx_fifo_inst(
    .clk        (PCLK),
    .rst_n      (PRESETn),
    .wr_en      (tx_fifo_wr_en),
    .wr_data    (tx_fifo_wdata),
    .rd_en      (tx_fifo_rd_en),
    .rd_data    (tx_data_in),
    .full       (tx_fifo_wr_full),
    .empty      (tx_fifo_rd_empty),
    .count      ()
);

// 6. 下载模块
uart_download #(
    .ADDR_WIDTH   (ADDR_WIDTH),
    .DATA_WIDTH   (DATA_WIDTH),
    .ALIGN_BYTES  (ALIGN_BYTES),
    .ALIGN_WIDTH  (ALIGN_WIDTH)
) u_uart_download(
    .clk                (PCLK),
    .rst_n              (PRESETn),
    .download_en        (download_en),
    .uart_rec_byte      (rx_fifo_rdata),
    .uart_rx_valid      (rx_fifo_rd_en),
    .itcm_download_en   (itcm_download_en_o),
    .itcm_download_addr (itcm_download_addr_o),
    .itcm_download_data (itcm_download_data_o),
    .dtcm_download_en   (dtcm_download_en_o),
    .dtcm_download_addr (dtcm_download_addr_o),
    .dtcm_download_data (dtcm_download_data_o),
    .download_done      (download_done)
);

assign tx_start = tx_fifo_rd_en;
// assign PREADY = (PSEL && PENABLE && (reg_sel == REG_SEL_0)) ? 
//                 (PWRITE ? tx_fifo_wr_en : rx_fifo_rd_en): 1'b1;
assign PREADY  = 1'b1;
assign PSLVERR  = 1'b0;

endmodule
