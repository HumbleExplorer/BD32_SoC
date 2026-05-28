`include "../../SoC_Config.sv"
`timescale 1ns / 1ps
module apb_uart #(
    parameter ADDR_WIDTH = `ADDR_WIDTH,
    parameter DATA_WIDTH = `DATA_WIDTH,
    parameter ALIGN_BYTES = `ALIGN_BYTES,
    parameter ALIGN_WIDTH = `ALIGN_WIDTH
)(
    // APB总线接口（4字节对齐）
    input   logic                       PCLK,        // 总线时钟
    input   logic                       PRESETn,      // 异步复位（低有效）
    input   logic   [ADDR_WIDTH-1:0]    PADDR,   // 32位地址（低2位必须为0）
    input   logic                       PSEL,  
    input   logic                       PENABLE,  
    input   logic                       PWRITE,
    input   logic   [DATA_WIDTH-1:0]    PWDATA,  // 32位写数据（仅[7:0]有效）
    output  logic   [DATA_WIDTH-1:0]    PRDATA,  // 32位读数据（仅[7:0]有效）
    output  logic                       PREADY,  
    output  logic                       PSLVERR, //1'b0
    // 中断输出
    output  logic                       irq_o,         // 中断请求
    // UART物理接口
    input   logic                       uart_rx_i,    // UART接收信号
    output  logic                       uart_tx_o,    // UART发送信号
    // 
    output  logic                       itcm_download_en_o,
    output  logic   [ADDR_WIDTH-1:0]    itcm_download_addr_o,
    output  logic   [DATA_WIDTH-1:0]    itcm_download_data_o,
    // DTCM下载写接口
    output  logic                       dtcm_download_en_o,
    output  logic   [ADDR_WIDTH-1:0]    dtcm_download_addr_o,
    output  logic   [DATA_WIDTH-1:0]    dtcm_download_data_o
);


// -------------------------- 本地参数与定义 --------------------------
localparam DLAB_BIT       = 7;                  // LCR[7]：除数锁存访问位（顶层仅需此位）
localparam FCR_CLR_RX     = 1;                  // FCR[1]：清接收FIFO
localparam FCR_CLR_TX     = 2;                  // FCR[2]：清发送FIFO

// 中断标识定义（IIR）- 严格遵循16550手册
localparam IIR_NO_INT     = 8'hC1;              // 无中断 (FIFO Enabled)
localparam IIR_RLS_INT    = 8'h06;              // 接收线状态中断 (最高优先级)
localparam IIR_RDA_INT    = 8'h04;              // 接收数据就绪
localparam IIR_TOUT_INT   = 8'h0C;              // 接收超时
localparam IIR_THRE_INT   = 8'h02;              // 发送保持寄存器空
localparam IIR_MSR_INT    = 8'h00;              // 调制解调器状态

// 32位地址解码：忽略低2位，使用 [5:2] 选择8个UART寄存器
typedef enum logic[3:0] {
    REG_SEL_0 = 4'b0000, // 0x00: RBR/THR/DLL (受DLAB控制)
    REG_SEL_1 = 4'b0001, // 0x04: IER/DLM     (受DLAB控制)
    REG_SEL_2 = 4'b0010, // 0x08: IIR (读) / FCR (写)
    REG_SEL_3 = 4'b0011, // 0x0C: LCR
    REG_SEL_4 = 4'b0100, // 0x10: MCR
    REG_SEL_5 = 4'b0101, // 0x14: LSR (只读)
    REG_SEL_6 = 4'b0110, // 0x18: MSR (只读)
    REG_SEL_7 = 4'b0111, // 0x1C: DBG_EN (只写)
    REG_SEL_8 = 4'b1000  // 0x20: DBG_DONE (只读)
} uart_reg_sel_e;

logic [3:0] reg_sel;

// -------------------------- 内部寄存器与信号 --------------------------
// 16550 核心寄存器
// 注意：此处divisor = SYS_CLK_FREQ/BAUD/16
logic[15:0]    divisor;        // 除数寄存器 {DLM[15:8], DLL[7:0]}
logic[3:0]     ier;            // 中断使能寄存器
logic[7:0]     iir;            // 中断标识寄存器（只读）
logic[7:0]     fcr;            // FIFO控制寄存器（只写）
logic[7:0]     lcr;            // 线控制寄存器（8位完整，直接传给子模块）
logic[7:0]     mcr;            // 调制解调器控制
logic[7:0]     lsr;            // 线状态寄存器（只读）
logic[7:0]     msr;            // 调制解调器状态（只读）

// 子模块接口信号（统一信号名+位宽）
(* mark_debug = "true" *)logic          clk_sample;     // 16倍波特率时钟
(* mark_debug = "true" *)logic          clk_uart;       // 1倍波特率时钟
logic[7:0]     rx_data_out;    // 接收数据
logic          rx_data_valid;  // 接收数据就绪（与uart_rx的rx_data_ready对接）
logic[3:0]     rx_err;         // 接收错误 {BI[3], FE[2], PE[1], OE[0]} 16550标准位序
logic[7:0]     tx_data_in;     // 发送数据
logic          tx_start;       // 发送启动
logic          tx_busy;        // 发送忙

// FIFO 接口
logic           rx_fifo_wr_en;
logic           rx_fifo_rd_en;
logic           rx_fifo_clr;
logic           tx_fifo_wr_en;
logic           tx_fifo_rd_en;
logic           tx_fifo_clr;
logic   [7:0]   rx_fifo_rdata;
logic   [7:0]   tx_fifo_wdata;
logic           rx_fifo_rd_empty;
logic           tx_fifo_rd_empty;
logic           rx_fifo_wr_full;
logic           tx_fifo_wr_full;
logic   [4:0]   rx_fifo_cnt;    // 接收FIFO计数（0~15，16550标准深度）
logic   [5:0]   timeout_cnt;    // 接收超时计数（0~63，对应4个字符时间）
logic           timeout;
logic           reg_rd_en,reg_wr_en;

logic           download_en;
logic           download_done;


assign  reg_sel = PADDR[5:2]; // 32位地址解码核心
assign  reg_rd_en   = PSEL & !PWRITE & PENABLE;
assign  reg_wr_en   = PSEL & PWRITE & PENABLE;
assign  timeout = timeout_cnt == 6'd63;


// -------------------------- 1. 寄存器写逻辑 --------------------------
always_ff @(posedge PCLK or negedge PRESETn) begin
    if (!PRESETn) begin
        divisor        <= #1 16'd0;
        ier            <= #1 4'd0;
        fcr            <= #1 8'hC0;      // FIFO默认使能
        lcr            <= #1 8'h03;      // 默认8N1，DLAB=0
        mcr            <= #1 8'd0;
        download_en    <= #1 1'b0;
    end else begin
        // FCR 独立写逻辑 (地址0x08)：读IIR，写FCR
        if (reg_wr_en && (uart_reg_sel_e'(reg_sel) == REG_SEL_2)) begin
            fcr <= #1 PWDATA[7:0];
        end
        // FIFO 自清除逻辑：硬件自动清零（写1有效，自动回0）
        if (fcr[FCR_CLR_RX])
            fcr[FCR_CLR_RX]  <= #1 1'b0;
        if (fcr[FCR_CLR_TX])
            fcr[FCR_CLR_TX]  <= #1 1'b0;

        // 其他寄存器写逻辑 (含DLAB复用判断)
        if (reg_wr_en) begin
            case (uart_reg_sel_e'(reg_sel))
                REG_SEL_0: begin // 0x00: THR/DLL
                    if (lcr[DLAB_BIT]) divisor[7:0] <= #1 PWDATA[7:0];
                end
                REG_SEL_1: begin // 0x04: IER/DLM
                    if (lcr[DLAB_BIT]) divisor[15:8] <= #1 PWDATA[7:0];
                    else ier <= #1 PWDATA[3:0]; // IER仅低4位有效
                end
                REG_SEL_3: begin // 0x0C: LCR
                    // Break位(bit6)为1时，强制DLAB(bit7)为0（16550手册要求）
                    lcr <= #1 PWDATA[6] ? (PWDATA[7:0] & 8'h7F) : PWDATA[7:0];
                end
                REG_SEL_4: mcr <= #1 PWDATA[7:0]; // 0x10: MCR
                REG_SEL_7: download_en <= #1 PWDATA[0]; // 0x1C: DBG_EN
                default: ; // 只读寄存器（IIR/LSR/MSR）忽略写操作
            endcase
        end
    end
end

//这里使用组合逻辑的原因是FIFO内有时序逻辑
// 发送模块空闲（~tx_busy）且发送 FIFO 非空时，触发读使能（读取数据并启动发送）。
assign  tx_fifo_rd_en = ~tx_fifo_rd_empty & ~tx_busy;
// CPU 写 THR 寄存器（地址 0x00，DLAB=0）且发送 FIFO 未写满时，触发写使能。
assign  tx_fifo_wr_en = reg_wr_en && uart_reg_sel_e'(reg_sel) == REG_SEL_0 && ~lcr[DLAB_BIT]
                        && ~tx_fifo_wr_full;
assign  tx_fifo_wdata = PWDATA[7:0];// THR
// 接收模块解析出有效数据（rx_data_valid）且接收 FIFO 未写满时，触发写使能。
assign  rx_fifo_wr_en = rx_data_valid & ~rx_fifo_wr_full;
// CPU 读 RBR 寄存器（地址 0x00，DLAB=0）且 FIFO 非空时，触发读使能（弹出 FIFO 数据）。
assign  rx_fifo_rd_en = ((reg_rd_en && uart_reg_sel_e'(reg_sel) == REG_SEL_0 && ~lcr[DLAB_BIT] )
                        || (download_en && ~download_done))
                        && ~rx_fifo_rd_empty;
// -------------------------- 2. 寄存器读逻辑 --------------------------
always_comb begin
    PRDATA  = {DATA_WIDTH{1'b0}}; // 默认返回32位全0
    if (reg_rd_en) begin
        case (uart_reg_sel_e'(reg_sel))
            REG_SEL_0: begin // 0x00: RBR/DLL
                if (lcr[DLAB_BIT]) PRDATA[7:0] = divisor[7:0];
                else begin
                    PRDATA[7:0] = rx_fifo_rdata;
                end
            end
            REG_SEL_1: begin // 0x04: IER/DLM
                if (lcr[DLAB_BIT]) PRDATA[7:0] = divisor[15:8];
                else PRDATA[7:0] = {4'd0, ier}; // 高4位补0
            end
            REG_SEL_2: PRDATA[7:0] = iir;  // 0x08: IIR（只读）
            REG_SEL_3: PRDATA[7:0] = lcr;  // 0x0C: LCR（读写）
            REG_SEL_4: PRDATA[7:0] = mcr;  // 0x10: MCR（只写，读返回当前值）
            REG_SEL_5: PRDATA[7:0] = lsr;  // 0x14: LSR（只读）
            REG_SEL_6: PRDATA[7:0] = msr;  // 0x18: MSR（只读）
            REG_SEL_8: PRDATA[1:0] = {download_en,download_done};//0x1C: DBG（只读）
            default: ;
        endcase
    end
end

// -------------------------- 3. LSR 状态更新 --------------------------
always_ff @(posedge PCLK or negedge PRESETn) begin
    if (!PRESETn) begin
        lsr <= #1 8'h60; // THRE=1, TEMT=1
    end else begin
        lsr[0] <= #1 ~rx_fifo_rd_empty; // DR：FIFO非空即数据就绪
        lsr[1] <= #1 rx_err[0] ? 1'b1 : (reg_rd_en && reg_sel == REG_SEL_5) ? 1'b0 : lsr[1]; // OE：溢出错误
        lsr[2] <= #1 rx_err[1] ? 1'b1 : (reg_rd_en && reg_sel == REG_SEL_5) ? 1'b0 : lsr[2]; // PE：奇偶错误
        lsr[3] <= #1 rx_err[2] ? 1'b1 : (reg_rd_en && reg_sel == REG_SEL_5) ? 1'b0 : lsr[3]; // FE：帧错误
        lsr[4] <= #1 rx_err[3] ? 1'b1 : (reg_rd_en && reg_sel == REG_SEL_5) ? 1'b0 : lsr[4]; // BI：断错误
        lsr[5] <= #1 tx_fifo_rd_empty; // THRE：发送FIFO空
        lsr[6] <= #1 (tx_fifo_rd_empty && ~tx_busy); // TEMT：发送器完全空（FIFO+移位寄存器）
        lsr[7] <= #1 (lsr[1] | lsr[2] | lsr[3] | lsr[4]); // EI：任意接收错误指示
    end
end

// -------------------------- 4. FIFO计数 + 接收超时 + 中断逻辑 --------------------------
always_ff @(posedge PCLK or negedge PRESETn) begin
    if (!PRESETn) begin
        timeout_cnt <= #1 6'd0;
        irq_o       <= #1 1'b0;
        iir         <= #1 IIR_NO_INT;
    end else begin
        // ===== 接收超时计数逻辑（0~63，对应4个字符时间） =====FIFO中至少有一个数据，且4个字符周期内没有操作
        if (rx_fifo_rd_empty || rx_fifo_wr_en || rx_fifo_rd_en) begin// 清零条件：FIFO空/新数据接收/数据读出
            timeout_cnt <= #1 6'd0; 
        end else if (timeout) begin
            timeout_cnt <= #1 6'd0; 
        end else begin
            timeout_cnt <= #1 timeout_cnt + 1'b1; // 未清零则计数+1，到63后保持
        end

        // ===== 中断优先级判定（RLS > RDA/TOUT > THRE > MSR） =====
        if (ier[2] && (lsr[1] | lsr[2] | lsr[3] | lsr[4])) begin
            irq_o <= #1 1'b1; iir <= #1 IIR_RLS_INT; // 接收线状态中断（最高优先级）
        end else if (ier[0] && rx_fifo_cnt >= get_trigger()) begin
            irq_o <= #1 1'b1; iir <= #1 timeout ? IIR_TOUT_INT : IIR_RDA_INT; // 接收数据/超时
        end else if (ier[1] && tx_fifo_rd_empty) begin
            irq_o <= #1 1'b1; iir <= #1 IIR_THRE_INT; // 发送FIFO空
        end else if (ier[3] && (msr[0] | msr[1] | msr[2] | msr[3])) begin
            irq_o <= #1 1'b1; iir <= #1 IIR_MSR_INT; // 调制解调器状态
        end else begin
            irq_o <= #1 1'b0; iir <= #1 IIR_NO_INT;  // 无中断
        end

        // ===== 中断清除逻辑 =====
        if (reg_rd_en) begin
            if (reg_sel == REG_SEL_2 && (iir == IIR_THRE_INT)) begin // 读IIR清THRE中断
                irq_o <= #1 1'b0; iir <= #1 IIR_NO_INT;
            end else if (reg_sel == REG_SEL_5 && (iir == IIR_RLS_INT)) begin // 读LSR清RLS中断
                irq_o <= #1 1'b0; iir <= #1 IIR_NO_INT;
            end else if (reg_sel == REG_SEL_6 && (iir == IIR_MSR_INT)) begin // 读MSR清MSR中断
                irq_o <= #1 1'b0; iir <= #1 IIR_NO_INT;
            end else if (reg_sel == REG_SEL_0 && !lcr[DLAB_BIT] && (iir[3:0] == IIR_RDA_INT[3:0] || iir[3:0] == IIR_TOUT_INT[3:0])) begin // 读RBR清RDA/TOUT中断
                irq_o <= #1 1'b0; iir <= #1 IIR_NO_INT;
            end
        end
    end
end

// -------------------------- 辅助函数：FIFO中断触发级别 --------------------------
function automatic logic[3:0] get_trigger();
    case (fcr[7:6])
        2'b00: return 4'd1;  // 1字节触发
        2'b01: return 4'd4;  // 4字节触发
        2'b10: return 4'd8;  // 8字节触发
        2'b11: return 4'd14; // 14字节触发
        default: return 4'd1;
    endcase
endfunction

// -------------------------- 子模块例化（核心：LCR合并为8位直接传递） --------------------------
// 1. 波特率时钟分频模块
uart_clk_div uart_clk_div_inst (
    .clk        (PCLK),
    .rst_n      (PRESETn),
    .divisor    (divisor),
    .clk_sample (clk_sample),
    .clk_uart   (clk_uart)
);

// 2. 接收模块：LCR合并为8位输入，子模块内部拆分
uart_rx u_uart_rx(
    .clk_sample         (clk_sample       ),
    .rst_n              (PRESETn          ),
    .rx_i               (uart_rx_i        ),
    .lcr                (lcr              ),
    .rx_fifo_wr_full    (rx_fifo_wr_full  ),
    .rx_o               (rx_data_out      ),
    .rx_valid_o         (rx_data_valid    ),
    .rx_err             (rx_err           )
);

// 3. 发送模块：LCR合并为8位输入，子模块内部拆分
uart_tx u_uart_tx(
    .clk_uart           (clk_uart  ),
    .rst_n              (PRESETn   ),
    .tx_i               (tx_data_in),
    .tx_start           (tx_start  ),
    .lcr                (lcr       ),
    .tx_o               (uart_tx_o ),
    .tx_busy            (tx_busy   )
);


// 4. 接收异步FIFO（16深度，8位宽，屏蔽悬空端口）
async_fifo #(.DEPTH(16), .WIDTH(8)) rx_fifo_inst(
    .wclk               (clk_sample       ),
    .rclk               (PCLK             ),
    .rst_n              (PRESETn          ),
    .clr                (rx_fifo_clr      ),
    .wr_en              (rx_fifo_wr_en    ),
    .rd_en              (rx_fifo_rd_en    ),
    .wr_data            (rx_data_out      ),
    .rd_data            (rx_fifo_rdata    ),
    .elements_num       (rx_fifo_cnt      ),
    .wr_full            (rx_fifo_wr_full  ),
    .rd_empty           (rx_fifo_rd_empty )
    // .almost_wr_full     (almost_wr_full   ),
    // .almost_rd_empty    (almost_rd_empty  )
);


// 5. 发送异步FIFO（16深度，8位宽，屏蔽悬空端口）
async_fifo #(.DEPTH(16), .WIDTH(8)) tx_fifo_inst (
    .wclk        (PCLK),
    .rclk        (clk_uart),
    .rst_n       (PRESETn),
    .clr         (tx_fifo_clr),
    .wr_en       (tx_fifo_wr_en),
    .rd_en       (tx_fifo_rd_en),
    .wr_data     (tx_fifo_wdata),
    .rd_data     (tx_data_in),
    .wr_full     (tx_fifo_wr_full),
    .rd_empty    (tx_fifo_rd_empty)
    // .almost_full (tx_fifo_almost_full),
    // .almost_empty(tx_fifo_almost_empty)
);

// 6. 下载模块：下载指令到ITCM
uart_download #(
    .ADDR_WIDTH  	(ADDR_WIDTH  ),
    .DATA_WIDTH  	(DATA_WIDTH  ),
    .ALIGN_BYTES 	(ALIGN_BYTES ),
    .ALIGN_WIDTH 	(ALIGN_WIDTH )
)u_uart_download(
    .clk            (PCLK           ),
    .rst_n          (PRESETn        ),
    .download_en    (download_en    ),
    .uart_rec_byte  (rx_fifo_rdata  ),
    .uart_rx_valid  (rx_fifo_rd_en  ),
    .itcm_download_en     (itcm_download_en_o   ),
    .itcm_download_addr   (itcm_download_addr_o ),
    .itcm_download_data   (itcm_download_data_o ),
    .dtcm_download_en     (dtcm_download_en_o   ),
    .dtcm_download_addr   (dtcm_download_addr_o ),
    .dtcm_download_data   (dtcm_download_data_o ),
    .download_done  (download_done  )
);

always_ff @(posedge clk_uart or negedge PRESETn) begin
    if (!PRESETn) begin
        tx_fifo_clr   <= #1 1'b0;
    end else begin
        // FIFO 自清除逻辑：硬件自动清零（写1有效，自动回0）
        if (fcr[FCR_CLR_TX])
            tx_fifo_clr    <= #1 1'b1;
        else
            tx_fifo_clr    <= #1 1'b0;
    end
end

always_ff @(posedge clk_sample or negedge PRESETn) begin
    if (!PRESETn) begin
        rx_fifo_clr   <= #1 1'b0;
    end else begin
        // FIFO 自清除逻辑：硬件自动清零（写1有效，自动回0）
        if (fcr[FCR_CLR_RX])
            rx_fifo_clr    <= #1 1'b1;
        else
            rx_fifo_clr    <= #1 1'b0;
    end
end
// always_ff @(posedge PCLK or negedge PRESETn) begin
//     PREADY <= #1 1'b1;
//     if (PSEL & ~lcr[DLAB_BIT] & reg_sel == REG_SEL_0)
//         if(PWRITE) begin
//             PREADY <= #1 PREADY ? ~PREADY : tx_fifo_wr_en;
//         end else begin
//             PREADY <= #1 rx_fifo_rd_en;
//         end
// end
assign PREADY = (PSEL && PENABLE && ~lcr[DLAB_BIT]) ? 
                (reg_sel == REG_SEL_0 ? 
                (PWRITE ? tx_fifo_wr_en : rx_fifo_rd_en) : 1'b1) : 1'b1;
assign tx_start = tx_fifo_rd_en;
assign PSLVERR = 1'b0;
endmodule