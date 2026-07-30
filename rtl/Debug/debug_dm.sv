// BD32 Debug Module (DM)
// 基于 SparrowRV jtag_dm.v 改编，系统 clk 时钟域
// 实现：halt/resume + GPR 读写 + dcsr/dpc（单步/ebreakm）
// System Bus Access 框架保留，第二步启用
`include "./../SoC_Config.sv"
timeunit 1ns;
timeprecision 1ps;

module debug_dm #(
    parameter DMI_ADDR_BITS = 6,
    parameter DMI_DATA_BITS = 32,
    parameter DMI_OP_BITS   = 2,
    parameter DMI_BITS      = DMI_ADDR_BITS + DMI_DATA_BITS + DMI_OP_BITS  // 40
)(
    input  logic                    clk,
    input  logic                    rst_n,

    // DTM 侧 CDC 接口
    // DTM → DM（请求）
    input  logic                    dtm_req_valid,
    input  logic [DMI_BITS-1:0]     dtm_req_data,
    output logic                    dm_req_ack,
    // DM → DTM（响应）
    output logic                    dm_resp_valid,
    output logic [DMI_BITS-1:0]     dm_resp_data,
    input  logic                    dtm_resp_ack,

    // CPU 寄存器堆接口
    output logic                    dbg_reg_we,
    output logic [4:0]              dbg_reg_addr,
    output logic [31:0]             dbg_reg_wdata,
    input  logic [31:0]             dbg_reg_rdata,

    // CPU 流水线控制
    output logic                    dbg_halt_req,     // 暂停请求
    input  logic                    dbg_halted,       // CPU 已暂停确认
    output logic                    dbg_resume_req,   // 恢复请求（一拍脉冲）
    output logic                    dbg_step,         // 单步模式
    output logic                    dbg_ebreakm,      // ebreak 进入 debug mode

    // Trigger（硬件断点）
    output logic                    trigger_en,       // 断点有效（execute match）
    output logic [31:0]             trigger_addr,     // 匹配地址
    input  logic                    trigger_hit,      // CPU 侧命中

    // Debug CSR 值（CPU 侧维护，DM 可读）
    input  logic [31:0]             dbg_dpc,          // 进入 debug 时的 PC
    output logic [31:0]             dbg_pc_wdata,     // resume 时加载的 PC 值

    // System Bus Access (SBA) 总线接口
    output logic                    sba_req_valid,    // 请求有效（一拍）
    output logic [31:0]             sba_addr,         // 访问地址
    output logic [31:0]             sba_wdata,        // 写数据
    output logic                    sba_write,        // 1=写 0=读
    output logic [2:0]              sba_size,         // 访问宽度 (2=word)
    input  logic                    sba_rsp_valid,    // 响应有效
    input  logic [31:0]             sba_rdata,        // 读回数据
    input  logic                    sba_error         // 访问错误
);

// ============================================================
// DMI 寄存器地址
// ============================================================
localparam ADDR_DATA0      = 6'h04;
localparam ADDR_DMCONTROL  = 6'h10;
localparam ADDR_DMSTATUS   = 6'h11;
localparam ADDR_HARTINFO   = 6'h12;
localparam ADDR_ABSTRACTCS = 6'h16;
localparam ADDR_COMMAND    = 6'h17;
localparam ADDR_SBCS       = 6'h38;
localparam ADDR_SBADDRESS0 = 6'h39;
localparam ADDR_SBDATA0    = 6'h3C;

// Debug CSR 编号（Abstract Command regno）
localparam REGNO_DCSR      = 16'h7B0;
localparam REGNO_DPC       = 16'h7B1;
localparam REGNO_DSCRATCH0 = 16'h7B2;
localparam REGNO_GPR_BASE  = 16'h1000;

// Trigger CSR 编号
localparam REGNO_TSELECT   = 16'h7A0;
localparam REGNO_TDATA1    = 16'h7A1;
localparam REGNO_TDATA2    = 16'h7A2;
localparam REGNO_TDATA3    = 16'h7A3;

// DMI OP
localparam OP_NOP   = 2'b00;
localparam OP_READ  = 2'b01;
localparam OP_WRITE = 2'b10;
localparam OP_SUCC  = 2'b00;

// ============================================================
// DM 内部寄存器
// ============================================================
logic [31:0] data0;
logic [31:0] dmcontrol_r;
logic [2:0]  abstractcs_cmderr;
logic        abstract_busy;     // abstract command 执行中（1 拍）
logic [31:0] dscratch0;

// Trigger 寄存器（1 个 mcontrol entry）
logic [31:0] tdata1_r;        // {type=2, dmode, ..., execute, ...}
logic [31:0] tdata2_r;        // 匹配地址

// dcsr 字段（DM 侧可写，CPU 侧只读）
logic        dcsr_step;       // dcsr[2]：单步
logic        dcsr_ebreakm;    // dcsr[15]：ebreak 进入 debug
logic [2:0]  dcsr_cause;      // dcsr[8:6]：进入原因（CPU 侧写入）

// 状态机
localparam S_IDLE = 2'b00;
localparam S_EXE  = 2'b01;
localparam S_END  = 2'b10;
logic [1:0] state;

// CDC 接收
logic                   rx_valid;
logic [DMI_BITS-1:0]    rx_data;
logic [DMI_BITS-1:0]    rx_data_r;

// 内部信号
logic [31:0] dmi_rsp_data;
logic        need_resp;
logic        is_read_reg;
logic        halt_req_r;
logic        resume_pulse;
logic        reg_we_r;
logic [4:0]  reg_addr_r;
logic [31:0] reg_wdata_r;

// resumeack 逻辑：检测 dbg_halted 下降沿（CPU 恢复运行）
logic        resume_ack_r;
logic        halted_d;        // dbg_halted 打一拍
wire         halted_fell = halted_d & ~dbg_halted;  // 1→0 下降沿

// dpc 寄存器：halt 时捕获 PC，调试器可写，resume 时加载回 CPU
logic [31:0] dpc_r;
assign dbg_pc_wdata = dpc_r;

// hartsel 跟踪（用于判断 hart 是否存在）
logic [9:0]  hartsel_r;
wire         hart_nonexistent = (hartsel_r != 10'd0);  // 仅 hart 0 存在

// ============================================================
// SBA 寄存器与状态机
// ============================================================
logic [31:0] sbaddress0_r;
logic [31:0] sbdata0_r;
// sbcs 字段
logic        sbreadonaddr;    // sbcs[20]
logic [2:0]  sbaccess;        // sbcs[19:17]
logic        sbautoincrement; // sbcs[16]
logic        sbreadondata;    // sbcs[15]
logic [2:0]  sberror;         // sbcs[14:12]
logic        sbbusyerror;     // sbcs[22]

// SBA 状态机
localparam SBA_IDLE  = 2'b00;
localparam SBA_READ  = 2'b01;
localparam SBA_WRITE = 2'b10;
localparam SBA_DONE  = 2'b11;
logic [1:0]  sba_state;
logic        sba_busy;

// SBA 总线输出
assign sba_req_valid = (sba_state == SBA_READ || sba_state == SBA_WRITE) && !sba_rsp_valid;
assign sba_addr      = sbaddress0_r;
assign sba_wdata     = sbdata0_r;
assign sba_write     = (sba_state == SBA_WRITE);
assign sba_size      = sbaccess;

// sbcs 读值组装（RISC-V Debug Spec 0.13 位域）
wire [31:0] sbcs_rdata = {
    3'b001,         // [31:29] sbversion = 1
    6'b0,           // [28:23] reserved
    sbbusyerror,    // [22]
    sba_busy,       // [21] sbbusy
    sbreadonaddr,   // [20]
    sbaccess,       // [19:17]
    sbautoincrement,// [16]
    sbreadondata,   // [15]
    sberror,        // [14:12]
    7'd32,          // [11:5] sbasize = 32-bit address
    1'b0,           // [4] sbaccess128
    1'b0,           // [3] sbaccess64
    1'b1,           // [2] sbaccess32 = 1（支持 32 位访问）
    1'b0,           // [1] sbaccess16
    1'b0            // [0] sbaccess8
};

// DMI 字段解析
wire [DMI_OP_BITS-1:0]   dmi_op   = rx_data_r[DMI_OP_BITS-1:0];
wire [DMI_DATA_BITS-1:0] dmi_data = rx_data_r[DMI_OP_BITS + DMI_DATA_BITS - 1 : DMI_OP_BITS];
wire [DMI_ADDR_BITS-1:0] dmi_addr = rx_data_r[DMI_BITS-1 : DMI_OP_BITS + DMI_DATA_BITS];

// dmstatus 构建（RISC-V Debug Spec 0.13 位域）
wire [31:0] dmstatus = {
    9'b0,           // [31:23] reserved
    1'b0,           // [22] impebreak
    2'b0,           // [21:20] reserved
    1'b0,           // [19] allhavereset
    1'b0,           // [18] anyhavereset
    resume_ack_r,   // [17] allresumeack
    resume_ack_r,   // [16] anyresumeack
    hart_nonexistent, // [15] allnonexistent
    hart_nonexistent, // [14] anynonexistent
    1'b0,           // [13] allunavail
    1'b0,           // [12] anyunavail
    ~dbg_halted & ~hart_nonexistent, // [11] allrunning
    ~dbg_halted & ~hart_nonexistent, // [10] anyrunning
    dbg_halted & ~hart_nonexistent,  // [9]  allhalted
    dbg_halted & ~hart_nonexistent,  // [8]  anyhalted
    1'b1,           // [7]  authenticated
    1'b0,           // [6]  authbusy
    1'b0,           // [5]  hasresethaltreq
    1'b0,           // [4]  confstrptrvalid
    4'h2            // [3:0] version = 2 (Spec 0.13)
};

// 输出
assign dbg_halt_req   = halt_req_r;
assign dbg_resume_req = resume_pulse;
assign dbg_step       = dcsr_step;
assign dbg_ebreakm    = dcsr_ebreakm;
assign dbg_reg_we     = reg_we_r;
assign dbg_reg_addr   = reg_addr_r;
assign dbg_reg_wdata  = reg_wdata_r;

// Trigger 输出：type==2 (mcontrol) && execute bit[2]
assign trigger_en   = (tdata1_r[31:28] == 4'h2) && tdata1_r[2];
assign trigger_addr = tdata2_r;

// ============================================================
// CDC 实例化
// ============================================================
// 接收 DTM 请求
debug_cdc_rx #(.DW(DMI_BITS)) u_rx (
    .clk         (clk),
    .rst_n       (rst_n),
    .req_i       (dtm_req_valid),
    .req_data_i  (dtm_req_data),
    .ack_o       (dm_req_ack),
    .recv_data_o (rx_data),
    .recv_rdy_o  (rx_valid)
);

// 发送响应给 DTM
debug_cdc_tx #(.DW(DMI_BITS)) u_tx (
    .clk        (clk),
    .rst_n      (rst_n),
    .ack_i      (dtm_resp_ack),
    .req_i      (need_resp),
    .req_data_i ({dmi_addr, dmi_rsp_data, OP_SUCC}),
    .idle_o     (),
    .req_o      (dm_resp_valid),
    .req_data_o (dm_resp_data)
);

// ============================================================
// DM 主状态机
// ============================================================
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state              <= S_IDLE;
        rx_data_r          <= '0;
        data0              <= '0;
        dmcontrol_r        <= '0;
        abstractcs_cmderr  <= '0;
        abstract_busy      <= 1'b0;
        dscratch0          <= '0;
        tdata1_r           <= 32'h2800_0000;  // type=2(mcontrol), dmode=1, disabled
        tdata2_r           <= '0;
        dcsr_step          <= 1'b0;
        dcsr_ebreakm       <= 1'b0;
        halt_req_r         <= 1'b0;
        resume_pulse       <= 1'b0;
        reg_we_r           <= 1'b0;
        reg_addr_r         <= '0;
        reg_wdata_r        <= '0;
        dmi_rsp_data       <= '0;
        need_resp          <= 1'b0;
        is_read_reg        <= 1'b0;
        resume_ack_r       <= 1'b0;
        halted_d           <= 1'b0;
        dpc_r              <= '0;
        hartsel_r          <= '0;
        // SBA
        sbaddress0_r       <= '0;
        sbdata0_r          <= '0;
        sbreadonaddr       <= 1'b0;
        sbaccess           <= 3'b010;  // 默认 32-bit
        sbautoincrement    <= 1'b0;
        sbreadondata       <= 1'b0;
        sberror            <= '0;
        sbbusyerror        <= 1'b0;
        sba_state          <= SBA_IDLE;
    end else begin
        // 默认值
        resume_pulse <= 1'b0;
        reg_we_r     <= 1'b0;
        abstract_busy <= 1'b0;  // 默认清除，写 command 时置 1

        // halted 边沿检测 + resumeack + dpc 捕获
        halted_d <= dbg_halted;
        if (halted_fell)
            resume_ack_r <= 1'b1;   // CPU 恢复运行，置 ack
        if (~halted_d & dbg_halted)
            dpc_r <= dbg_dpc;       // CPU 进入 halt，捕获当前 PC

        case (state)
            // ------------------------------------------------
            S_IDLE: begin
                if (rx_valid) begin
                    rx_data_r <= rx_data;
                    state     <= S_EXE;
                end
            end

            // ------------------------------------------------
            S_EXE: begin
                state     <= S_END;
                need_resp <= 1'b1;

                case (dmi_op)
                    // ======== 读操作 ========
                    OP_READ: begin
                        case (dmi_addr)
                            ADDR_DMSTATUS:   dmi_rsp_data <= dmstatus;
                            ADDR_DMCONTROL:  dmi_rsp_data <= dmcontrol_r;
                            ADDR_HARTINFO:   dmi_rsp_data <= 32'h0;
                            ADDR_ABSTRACTCS: dmi_rsp_data <= {20'h1000, abstract_busy, abstractcs_cmderr, 8'h03};
                            ADDR_DATA0: begin
                                if (is_read_reg)
                                    dmi_rsp_data <= dbg_reg_rdata;
                                else
                                    dmi_rsp_data <= data0;
                                is_read_reg <= 1'b0;
                            end
                            ADDR_SBCS:      dmi_rsp_data <= sbcs_rdata;
                            ADDR_SBADDRESS0: dmi_rsp_data <= sbaddress0_r;
                            ADDR_SBDATA0: begin
                                dmi_rsp_data <= sbdata0_r;
                                // sbreadondata：读完 sbdata0 后自动发起下一次读
                                if (sbreadondata && sba_state == SBA_IDLE)
                                    sba_state <= SBA_READ;
                            end
                            default: dmi_rsp_data <= '0;
                        endcase
                    end

                    // ======== 写操作 ========
                    OP_WRITE: begin
                        dmi_rsp_data <= '0;
                        case (dmi_addr)
                            // ---- dmcontrol ----
                            ADDR_DMCONTROL: begin
                                if (dmi_data[0] == 1'b0) begin
                                    // DM 复位
                                    halt_req_r        <= 1'b0;
                                    abstractcs_cmderr <= '0;
                                    dcsr_step         <= 1'b0;
                                    dcsr_ebreakm      <= 1'b0;
                                    resume_ack_r      <= 1'b0;
                                    hartsel_r         <= '0;
                                    dmcontrol_r       <= dmi_data;
                                end else begin
                                    dmcontrol_r <= (dmi_data & ~(32'h3FFFC0)) | 32'h10000;
                                    hartsel_r   <= dmi_data[25:16];
                                    if (dmi_data[31]) begin
                                        // haltreq
                                        halt_req_r <= 1'b1;
                                    end else if (dmi_data[30] && (halt_req_r || dbg_halted)) begin
                                        // resumereq：CPU 处于 halt 状态即可 resume
                                        // （含外部 haltreq、单步 step-halt、ebreak 等场景）
                                        halt_req_r   <= 1'b0;
                                        resume_pulse <= 1'b1;
                                        resume_ack_r <= 1'b0;  // 清 ack，等 CPU 真正恢复后再置
                                    end
                                end
                            end

                            // ---- command (Abstract Command) ----
                            ADDR_COMMAND: begin
                                abstract_busy <= 1'b1;  // 命令处理中，下一拍 data0 才有效
                                if (dmi_data[31:24] == 8'h0) begin  // cmdtype=0: Access Register
                                    if (dmi_data[22:20] > 3'h2) begin
                                        abstractcs_cmderr <= 3'b010;  // unsupported size
                                    end else begin
                                        abstractcs_cmderr <= '0;
                                        if (dmi_data[18] == 1'b0) begin  // postexec=0
                                            if (dmi_data[16] == 1'b0) begin
                                                // ---- 读寄存器 ----
                                                if (dmi_data[15:0] == REGNO_DCSR) begin
                                                    // 读 dcsr：组装 {xdebugver, cause, step, ebreakm}
                                                    data0 <= {4'h4, 12'b0, 1'b0, 3'b0,
                                                              1'b0, 1'b0, 1'b0, 1'b0,
                                                              1'b0, 1'b0, 1'b0,
                                                              dcsr_cause, 1'b0, 1'b0,
                                                              dcsr_step, dcsr_ebreakm, 1'b0};
                                                end else if (dmi_data[15:0] == REGNO_DPC) begin
                                                    data0 <= dpc_r;
                                                end else if (dmi_data[15:0] == REGNO_DSCRATCH0) begin
                                                    data0 <= dscratch0;
                                                end else if (dmi_data[15:0] >= REGNO_GPR_BASE && dmi_data[15:0] < REGNO_GPR_BASE + 16'd32) begin
                                                    // 读 GPR
                                                    reg_addr_r  <= dmi_data[4:0];
                                                    is_read_reg <= 1'b1;
                                                end else if (dmi_data[15:0] == REGNO_TSELECT) begin
                                                    data0 <= 32'd0;  // 仅 1 个 trigger (index 0)
                                                end else if (dmi_data[15:0] == REGNO_TDATA1) begin
                                                    data0 <= tdata1_r;
                                                end else if (dmi_data[15:0] == REGNO_TDATA2) begin
                                                    data0 <= tdata2_r;
                                                end else if (dmi_data[15:0] == REGNO_TDATA3) begin
                                                    data0 <= 32'd0;
                                                end
                                            end else begin
                                                // ---- 写寄存器 ----
                                                if (dmi_data[15:0] == REGNO_DCSR) begin
                                                    dcsr_step    <= data0[2];
                                                    dcsr_ebreakm <= data0[15];
                                                end else if (dmi_data[15:0] == REGNO_DPC) begin
                                                    dpc_r <= data0;
                                                end else if (dmi_data[15:0] == REGNO_DSCRATCH0) begin
                                                    dscratch0 <= data0;
                                                end else if (dmi_data[15:0] >= REGNO_GPR_BASE && dmi_data[15:0] < REGNO_GPR_BASE + 16'd32) begin
                                                    // 写 GPR
                                                    reg_we_r    <= 1'b1;
                                                    reg_addr_r  <= dmi_data[4:0];
                                                    reg_wdata_r <= data0;
                                                end else if (dmi_data[15:0] == REGNO_TDATA1) begin
                                                    tdata1_r <= data0;
                                                end else if (dmi_data[15:0] == REGNO_TDATA2) begin
                                                    tdata2_r <= data0;
                                                end
                                            end
                                        end
                                    end
                                end else begin
                                    abstractcs_cmderr <= 3'b001;  // unsupported cmdtype
                                end
                            end

                            // ---- data0 ----
                            ADDR_DATA0: data0 <= dmi_data;

                            // ---- sbcs ----
                            ADDR_SBCS: begin
                                sbreadonaddr    <= dmi_data[20];
                                sbaccess        <= dmi_data[19:17];
                                sbautoincrement <= dmi_data[16];
                                sbreadondata    <= dmi_data[15];
                                // W1C: sberror 和 sbbusyerror
                                if (|dmi_data[14:12]) sberror     <= '0;
                                if (dmi_data[22])     sbbusyerror <= 1'b0;
                            end

                            // ---- sbaddress0 ----
                            ADDR_SBADDRESS0: begin
                                sbaddress0_r <= dmi_data;
                                // sbreadonaddr：写地址后自动发起读
                                if (sbreadonaddr && sba_state == SBA_IDLE)
                                    sba_state <= SBA_READ;
                            end

                            // ---- sbdata0 ----
                            ADDR_SBDATA0: begin
                                if (sba_state != SBA_IDLE) begin
                                    // 忙时写入 → sbbusyerror
                                    sbbusyerror <= 1'b1;
                                end else begin
                                    sbdata0_r <= dmi_data;
                                    sba_state <= SBA_WRITE;
                                end
                            end

                            default: ;
                        endcase
                    end

                    // ======== NOP ========
                    OP_NOP: dmi_rsp_data <= '0;

                    default: dmi_rsp_data <= '0;
                endcase
            end

            // ------------------------------------------------
            S_END: begin
                state     <= S_IDLE;
                need_resp <= 1'b0;
            end

            default: state <= S_IDLE;
        endcase

        // ============================================================
        // SBA 状态机（独立于 DMI 状态机，每拍运行）
        // ============================================================
        case (sba_state)
            SBA_IDLE: ; // 等待 DMI  handler 触发

            SBA_READ: begin
                if (sba_rsp_valid) begin
                    sbdata0_r <= sba_rdata;
                    if (sba_error) sberror <= 3'b010;  // bus error
                    if (sbautoincrement)
                        sbaddress0_r <= sbaddress0_r + (32'd1 << sbaccess);
                    sba_state <= SBA_IDLE;
                end
            end

            SBA_WRITE: begin
                if (sba_rsp_valid) begin
                    if (sba_error) sberror <= 3'b010;
                    if (sbautoincrement)
                        sbaddress0_r <= sbaddress0_r + (32'd1 << sbaccess);
                    sba_state <= SBA_IDLE;
                end
            end

            default: sba_state <= SBA_IDLE;
        endcase
    end
end

// sba_busy 组合输出
assign sba_busy = (sba_state != SBA_IDLE);

// dcsr_cause 动态更新：step=4, halt=3
logic        stepped;       // 上次 resume 是单步
logic [2:0]  dcsr_cause_r;
wire         halted_rose = ~halted_d & dbg_halted;  // CPU 重新 halt

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        stepped      <= 1'b0;
        dcsr_cause_r <= 3'd3;
    end else begin
        if (resume_pulse && dcsr_step)
            stepped <= 1'b1;
        if (halted_rose) begin
            dcsr_cause_r <= stepped ? 3'd4 : 3'd3;
            stepped      <= 1'b0;
        end
    end
end

assign dcsr_cause = dcsr_cause_r;

endmodule
