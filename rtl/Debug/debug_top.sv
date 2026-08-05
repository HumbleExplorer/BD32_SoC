// BD32 Debug 顶层
// 例化 JTAG TAP (TCK域) + Debug Module (clk域)
// 对外暴露：JTAG 4线 + CPU 调试接口
`include "./../SoC_Config.sv"
timeunit 1ns;
timeprecision 1ps;

module debug_top (
    // 系统时钟/复位
    input  logic            clk,
    input  logic            rst_n,

    // JTAG 引脚（来自 bd32_board_top）
    input  logic            tck,
    input  logic            tms,
    input  logic            tdi,
    output logic            tdo,

    // CPU 寄存器堆接口
    output logic            dbg_reg_we,
    output logic [4:0]      dbg_reg_addr,
    output logic [31:0]     dbg_reg_wdata,
    input  logic [31:0]     dbg_reg_rdata,

    // CPU 流水线控制
    output logic            dbg_halt_req,
    input  logic            dbg_halted,
    output logic            dbg_resume_req,
    output logic            dbg_step,
    output logic            dbg_ebreakm,

    // Trigger（硬件断点）
    output logic            trigger_en,
    output logic [31:0]     trigger_addr,
    input  logic            trigger_hit,

    // Debug CSR
    input  logic [31:0]     dbg_dpc,
    output logic [31:0]     dbg_pc_wdata,

    // System Bus Access (SBA) 总线接口
    output logic            sba_req_valid,
    output logic [31:0]     sba_addr,
    output logic [31:0]     sba_wdata,
    output logic            sba_write,
    output logic [2:0]      sba_size,
    input  logic            sba_rsp_valid,
    input  logic [31:0]     sba_rdata,
    input  logic            sba_error,

    // Debug CSR（Abstract 通用 CSR 读写）
    output logic            dbg_csr_we,
    output logic [11:0]     dbg_csr_addr,
    output logic [31:0]     dbg_csr_wdata,
    input  logic [31:0]     dbg_csr_rdata,

    // 复位控制（ndmreset 复位 SoC，DM 自身不复位）
    output logic            ndmreset
);

localparam DMI_ADDR_BITS = 6;
localparam DMI_DATA_BITS = 32;
localparam DMI_OP_BITS   = 2;
localparam DMI_BITS      = DMI_ADDR_BITS + DMI_DATA_BITS + DMI_OP_BITS;

// TAP ↔ DM 之间的 CDC 信号
logic                    dtm_req_valid;
logic [DMI_BITS-1:0]     dtm_req_data;
logic                    dm_req_ack;
logic                    dm_resp_valid;
logic [DMI_BITS-1:0]     dm_resp_data;
logic                    dtm_resp_ack;



// ============================================================
// JTAG TAP + DTM（TCK 时钟域）
// ============================================================
jtag_tap #(
    .DMI_ADDR_BITS (DMI_ADDR_BITS),
    .DMI_DATA_BITS (DMI_DATA_BITS),
    .DMI_OP_BITS   (DMI_OP_BITS)
) u_tap (
    .rst_n          (rst_n),
    .tck            (tck),
    .tms            (tms),
    .tdi            (tdi),
    .tdo            (tdo),
    // DTM → DM
    .dtm_req_valid  (dtm_req_valid),
    .dtm_req_data   (dtm_req_data),
    .dm_req_ack     (dm_req_ack),
    // DM → DTM
    .dm_resp_valid  (dm_resp_valid),
    .dm_resp_data   (dm_resp_data),
    .dtm_resp_ack   (dtm_resp_ack)
);

// ============================================================
// Debug Module（系统 clk 时钟域）
// ============================================================
debug_dm #(
    .DMI_ADDR_BITS (DMI_ADDR_BITS),
    .DMI_DATA_BITS (DMI_DATA_BITS),
    .DMI_OP_BITS   (DMI_OP_BITS)
) u_dm (
    .clk            (clk),
    .rst_n          (rst_n),
    // DTM 侧
    .dtm_req_valid  (dtm_req_valid),
    .dtm_req_data   (dtm_req_data),
    .dm_req_ack     (dm_req_ack),
    .dm_resp_valid  (dm_resp_valid),
    .dm_resp_data   (dm_resp_data),
    .dtm_resp_ack   (dtm_resp_ack),
    // CPU 寄存器堆
    .dbg_reg_we     (dbg_reg_we),
    .dbg_reg_addr   (dbg_reg_addr),
    .dbg_reg_wdata  (dbg_reg_wdata),
    .dbg_reg_rdata  (dbg_reg_rdata),
    // CPU 流水线
    .dbg_halt_req   (dbg_halt_req),
    .dbg_halted     (dbg_halted),
    .dbg_resume_req (dbg_resume_req),
    .dbg_step       (dbg_step),
    .dbg_ebreakm    (dbg_ebreakm),
    // Trigger
    .trigger_en     (trigger_en),
    .trigger_addr   (trigger_addr),
    .trigger_hit    (trigger_hit),
    // Debug CSR
    .dbg_dpc        (dbg_dpc),
    .dbg_pc_wdata   (dbg_pc_wdata),
    // SBA 总线
    .sba_req_valid  (sba_req_valid),
    .sba_addr       (sba_addr),
    .sba_wdata      (sba_wdata),
    .sba_write      (sba_write),
    .sba_size       (sba_size),
    .sba_rsp_valid  (sba_rsp_valid),
    .sba_rdata      (sba_rdata),
    .sba_error      (sba_error),
    // Debug CSR
    .dbg_csr_we     (dbg_csr_we),
    .dbg_csr_addr   (dbg_csr_addr),
    .dbg_csr_wdata  (dbg_csr_wdata),
    .dbg_csr_rdata  (dbg_csr_rdata),
    .ndmreset       (ndmreset)
);

endmodule
