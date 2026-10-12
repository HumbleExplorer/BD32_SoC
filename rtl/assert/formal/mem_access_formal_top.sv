// =============================================================================
// mem_access_formal_top.sv — Mem_Access 形式验证 harness（SymbiYosys）
// =============================================================================
// 断言在 Mem_Access.sv 内部（`ifdef FORMAL 区）：
//   · 拆分 FSM 有界完成（最终完成性，需总线公平性假设——见模块内 assume）
//   · 拆分期间锁存 rvalid 恒 0（rvalid 提交门约定）
//   · P3 收尾态结构 / split_stall 约定
// 输入全自由穷举；dtcm_rdata/rd_bus_data 自由意味着本环境只证控制平面，
// 不证拆分数据合并的语义正确性（后者由 custom_asm 非对齐用例仿真覆盖）。
// =============================================================================

module mem_access_formal_top #(
    parameter ADDR_WIDTH   = 32,
    parameter DATA_WIDTH   = 32,
    parameter ALIGN_WIDTH  = 2,
    parameter ALIGN_BYTES  = 4
)(
    input logic clk,
    input logic rst_n
);

    logic                      ex_mem_stall;
    logic                      ex_mem_flush;
    logic [ADDR_WIDTH-1:0]     access_addr;
    logic                      access_en;
    logic                      access_wr;
    logic                      bus_tran_done;
    logic [DATA_WIDTH-1:0]     dtcm_rdata;
    logic [DATA_WIDTH-1:0]     itcm_rdata;
    logic [DATA_WIDTH-1:0]     rd_bus_data;
    logic [2:0]                access_func3;
    logic [DATA_WIDTH-1:0]     access_wdata_raw;

    // DUT 输出（必须显式声明，否则 Yosys 隐式 1-bit wire 会让断言静默失真）
    logic                      dtcm_sel, bus_sel, apb_sel;
    logic                      itcm_store_sel, itcm_load_sel;
    logic                      split_misaligned, split_active, split_p2;
    logic                      split_xfer, split_xfer2, split_xfer_off;
    logic [ADDR_WIDTH-1:0]     split_base, split_addr, split_addr_use;
    logic                      split_stall, split_wen_p1, split_wen, split_wr;
    logic [DATA_WIDTH-1:0]     split_wdata_p1, split_wdata;
    logic [ALIGN_BYTES-1:0]    split_wmask_p1, split_wmask;
    logic [DATA_WIDTH-1:0]     func3_expanded_data;
    logic                      tcm_rvalid, bus_rvalid;

    // 复位时序假设：初始 1 拍 rst_n=0，此后恒 1
    logic f_past_valid = 1'b0;
    always_ff @(posedge clk) f_past_valid <= 1'b1;
    always_ff @(posedge clk) begin
        if (!f_past_valid) assume (!rst_n);
        else               assume (rst_n);
    end

    Mem_Access #(
        .ADDR_WIDTH  (ADDR_WIDTH),
        .DATA_WIDTH  (DATA_WIDTH),
        .ALIGN_WIDTH (ALIGN_WIDTH),
        .ALIGN_BYTES (ALIGN_BYTES)
    ) dut (
        .clk               (clk),
        .rst_n             (rst_n),
        .ex_mem_stall      (ex_mem_stall),
        .ex_mem_flush      (ex_mem_flush),
        .access_addr       (access_addr),
        .access_en         (access_en),
        .access_wr         (access_wr),
        .bus_tran_done     (bus_tran_done),
        .dtcm_rdata        (dtcm_rdata),
        .itcm_rdata        (itcm_rdata),
        .rd_bus_data       (rd_bus_data),
        .access_func3      (access_func3),
        .access_wdata_raw  (access_wdata_raw),
        .dtcm_sel          (dtcm_sel),
        .bus_sel           (bus_sel),
        .apb_sel           (apb_sel),
        .itcm_store_sel    (itcm_store_sel),
        .itcm_load_sel     (itcm_load_sel),
        .split_misaligned  (split_misaligned),
        .split_active      (split_active),
        .split_p2          (split_p2),
        .split_xfer        (split_xfer),
        .split_xfer2       (split_xfer2),
        .split_xfer_off    (split_xfer_off),
        .split_base        (split_base),
        .split_addr        (split_addr),
        .split_addr_use    (split_addr_use),
        .split_stall       (split_stall),
        .split_wen_p1      (split_wen_p1),
        .split_wen         (split_wen),
        .split_wr          (split_wr),
        .split_wdata_p1    (split_wdata_p1),
        .split_wdata       (split_wdata),
        .split_wmask_p1    (split_wmask_p1),
        .split_wmask       (split_wmask),
        .func3_expanded_data (func3_expanded_data),
        .tcm_rvalid        (tcm_rvalid),
        .bus_rvalid        (bus_rvalid)
    );

endmodule
