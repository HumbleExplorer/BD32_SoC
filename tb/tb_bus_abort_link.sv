// ============================================================================
// tb_bus_abort_link.sv — 主机强拆（bus_timeout DECERR）→ 桥侧回收 衔接约定验证
//
// BD32 — RV32IM Pipelined RISC-V SoC
// Copyright (c) 2026 BD32 Project
// SPDX-License-Identifier: Apache-2.0
//
// 背景：bus_timeout 测试（force PREADY=0）的"超时"由桥层 APB_TO_VAL（512 拍）
// 先行消化，主机层 bus_timeout（1024 拍）从未真实触发——双层超时衔接约定
// （bind_bus_timeout.sv）在该场景下无可观察事件。本 TB 用**真实 AXI_Lite_Master**
// （Bus_Access 全链）访问**未路由段（0xD000_0000，无从机选中、无握手）**，
// 使主机 bus_timeout 真实触发，验证：
//   A1 主机强拆返回 DECERR（bus_error=2'b11）有界完成；
//   A2 强拆拍起，桥内 apb_master 至多 APB_TO_VAL+GRACE 拍回 IDLE（衔接窗口）；
//   A3 窗口内桥不得接受新 APB 事务（半事务不被叠加）。
// 断言复用 rtl/assert/bind_bus_timeout.sv 的 bus_timeout_link_chk（bind 到
// 本 TB 的实例层次——bind 目标 SoC_top 换成 tb 顶层等价结构）。
// ============================================================================
timeunit 1ns;
timeprecision 1ps;

module tb_bus_abort_link;

localparam logic [31:0] DEAD_ADDR = 32'hD000_0000;   // 未路由段
localparam int unsigned MASTER_TIMEOUT = 1024;        // 与 SoC_Config BUS_TIMEOUT（非 FORMAL）一致

int error_count = 0;
logic clk, rst_n;

initial begin
    clk = 1'b0;
    forever #10 clk = ~clk;
end

initial begin
    rst_n = 1'b0;
    #200;
    rst_n = 1'b1;
end

// =================== CPU 侧请求接口 ===================
logic        req_valid, req_write;
logic [31:0] req_addr, req_wdata;
logic [3:0]  req_wmask;
logic        bus_ready, bus_tran_done;
logic [31:0] bus_rdata;
logic [1:0]  bus_error;

// =================== DUT：Bus_Access（含真实 AXI_Lite_Master）===================

axi_if axi_bus ();   // Bus_Access ↔ 互联
axi_if axi_apb ();   // 互联.m0 ↔ 桥
axi_if axi_m1 ();    // 互联.m1 ↔ err_slave
axi_if axi_m2 ();    // 互联.m2 ↔ err_slave

Bus_Access #(
    .ADDR_WIDTH (32),
    .DATA_WIDTH (32),
    .STRB_WIDTH (4),
    .ID_WIDTH   (4),
    .LEN_WIDTH  (8)
) u_bus_access (
    .clk            (clk),
    .rst_n          (rst_n),
    .i_transfer     (req_valid),
    .i_write        (req_write),
    .i_addr         (req_addr),
    .i_wdata        (req_wdata),
    .i_wmask        (req_wmask),
    .o_bus_tran_done(bus_tran_done),
    .o_bus_ready    (bus_ready),
    .o_bus_rdata    (bus_rdata),
    .o_bus_error    (bus_error),
    .m           (axi_bus)
);

// =================== DUT：AXI_Interconnect + err_slave×2 + 桥 ===================
// （与 SoC_top 同构；APB 侧挂桩从机可 force 挂死，本 TB 主测未路由段故桩从简）
logic [3:0]  m0_awid, m0_arid, m0_bid, m0_rid;
logic [31:0] m0_awaddr, m0_araddr, m0_wdata, m0_rdata;
logic [7:0]  m0_awlen, m0_arlen;
logic [2:0]  m0_awsize, m0_arsize;
logic [1:0]  m0_awburst, m0_arburst, m0_bresp, m0_rresp;
logic        m0_awlock, m0_arlock, m0_wlast, m0_rlast;
logic [3:0]  m0_awcache, m0_arcache, m0_awqos, m0_arqos, m0_awregion, m0_arregion;
logic [2:0]  m0_awprot, m0_arprot;
logic [3:0]  m0_wstrb;
logic        m0_awvalid, m0_awready, m0_wvalid, m0_wready, m0_bvalid, m0_bready;
logic        m0_arvalid, m0_arready, m0_rvalid, m0_rready;

logic [3:0]  m1_awid, m1_arid, m1_bid, m1_rid;
logic [31:0] m1_awaddr, m1_araddr, m1_wdata, m1_rdata;
logic [7:0]  m1_awlen, m1_arlen;
logic [2:0]  m1_awsize, m1_arsize;
logic [1:0]  m1_awburst, m1_arburst, m1_bresp, m1_rresp;
logic        m1_awlock, m1_arlock, m1_wlast, m1_rlast;
logic [3:0]  m1_awcache, m1_arcache, m1_awqos, m1_arqos, m1_awregion, m1_arregion;
logic [2:0]  m1_awprot, m1_arprot;
logic [3:0]  m1_wstrb;
logic        m1_awvalid, m1_awready, m1_wvalid, m1_wready, m1_bvalid, m1_bready;
logic        m1_arvalid, m1_arready, m1_rvalid, m1_rready;

logic [3:0]  m2_awid, m2_arid, m2_bid, m2_rid;
logic [31:0] m2_awaddr, m2_araddr, m2_wdata, m2_rdata;
logic [7:0]  m2_awlen, m2_arlen;
logic [2:0]  m2_awsize, m2_arsize;
logic [1:0]  m2_awburst, m2_arburst, m2_bresp, m2_rresp;
logic        m2_awlock, m2_arlock, m2_wlast, m2_rlast;
logic [3:0]  m2_awcache, m2_arcache, m2_awqos, m2_arqos, m2_awregion, m2_arregion;
logic [2:0]  m2_awprot, m2_arprot;
logic [3:0]  m2_wstrb;
logic        m2_awvalid, m2_awready, m2_wvalid, m2_wready, m2_bvalid, m2_bready;
logic        m2_arvalid, m2_arready, m2_rvalid, m2_rready;

AXI_Interconnect #(
    .ADDR_WIDTH (32), .DATA_WIDTH (32), .STRB_WIDTH (4), .ID_WIDTH (4)
) u_AXI_Interconnect (
    .clk(rst_n ? clk : clk), .rst_n(rst_n),
    .s           (axi_bus),
    .m0          (axi_apb),
    .m1          (axi_m1),
    .m2          (axi_m2)
);

axi_err_slave #(.ADDR_WIDTH(32), .DATA_WIDTH(32), .STRB_WIDTH(4), .ID_WIDTH(4)) u_err_mrom (
    .clk(clk), .rst_n(rst_n),
    .s           (axi_m1)
);

axi_err_slave #(.ADDR_WIDTH(32), .DATA_WIDTH(32), .STRB_WIDTH(4), .ID_WIDTH(4)) u_err_ddr (
    .clk(clk), .rst_n(rst_n),
    .s           (axi_m2)
);

// 桥 + APB_Interconnect + 空闲从机槽（本 TB 不测 APB 路径，但保持链完整以复现拓扑）
logic [31:0] bridge_paddr, bridge_pwdata, bridge_prdata;
logic [3:0]  bridge_pstrb;
logic        bridge_psel, bridge_penable, bridge_pwrite, bridge_pready, bridge_pslverr;
logic [15:0] apb_psel;
logic [31:0] apb_prdata [16];
logic [15:0] apb_pready;
logic [15:0] apb_pslverr;

AXI_APB_Bridge #(
    .ADDR_WIDTH(32), .DATA_WIDTH(32), .STRB_WIDTH(4), .ID_WIDTH(4), .LEN_WIDTH(8)
) u_AXI_APB_Bridge (
    .clk(clk), .rst_n(rst_n),
    .s           (axi_apb),
    .PADDR(bridge_paddr), .PSEL(bridge_psel), .PENABLE(bridge_penable),
    .PWRITE(bridge_pwrite), .PSTRB(bridge_pstrb), .PWDATA(bridge_pwdata),
    .PRDATA(bridge_prdata), .PREADY(bridge_pready), .PSLVERR(bridge_pslverr)
);

APB_Interconnect #(.PADDR_WIDTH(32), .PDATA_WIDTH(32), .NUM_SLAVES(16)) u_apb_interconnect (
    .PADDR(bridge_paddr), .PSEL(bridge_psel),
    .i_prdata(apb_prdata), .i_pready(apb_pready), .i_pslverr(apb_pslverr),
    .o_psel(apb_psel),
    .PRDATA(bridge_prdata), .PREADY(bridge_pready), .PSLVERR(bridge_pslverr)
);

generate
    for (genvar g = 0; g < 16; g = g + 1) begin : gen_idle
        assign apb_prdata[g]   = 32'd0;
        assign apb_pready[g]   = 1'b1;
        assign apb_pslverr[g]  = 1'b0;
    end
endgenerate

// =================== 跨层检查器（与 bind_bus_timeout 同一模块）==================
// 直接实例化（本 TB 顶层就是被观察环境，无需 bind）：
//   层次引用指向本 TB 的 u_bus_access.u_AXI_Lite_Master 与 u_AXI_APB_Bridge.u_apb_master
bus_timeout_link_chk #(
    .APB_TO_VAL(512),
    .GRACE     (4)
) u_chk_btlink (
    .clk   (clk),
    .rst_n (rst_n)
);

// =================== 主流程 ===================
task automatic check(input bit cond, input string msg);
    if (!cond) begin
        error_count++;
        $display("  [FAIL] %s", msg);
    end else begin
        $display("  [ok] %s", msg);
    end
endtask

initial begin
    req_valid = 1'b0;
    req_write = 1'b0;
    req_addr  = 32'h0;
    req_wdata = 32'h0;
    req_wmask = 4'hF;
    wait (rst_n === 1'b1);
    repeat (4) @(posedge clk);

    $display("============================================================");
    $display("  Bus Abort Link Test: master bus_timeout -> bridge recovery");
    $display("============================================================");

    // A1：写未路由段 → 主机 bus_timeout 强拆 → DECERR，有界完成
    // 注意：请求-响应接口的 req_ready 只在 DONE/IDLE 为高——本场景无从机握手，
    // req_valid 挂住后每笔 1024 拍超时即被重发（req_ready 在 DONE 态又高）。
    // 为验证"单笔强拆→回收"衔接，用计数器在超时首拍撤下请求。
    @(posedge clk);
    req_valid <= 1'b1;
    req_write <= 1'b1;
    req_addr  <= DEAD_ADDR;
    req_wdata <= 32'hCAFE_F00D;
    begin : single_wr
        int unsigned n;
        n = 0;
        forever begin
            @(posedge clk);
            n++;
            if (bus_tran_done) break;            // 响应完成（DECERR）
            if (n >= MASTER_TIMEOUT + 8) begin   // 超时首拍附近撤下，只发一笔
                req_valid <= 1'b0;
            end
            if (n >= MASTER_TIMEOUT + 64) begin
                $display("  [FAIL] write not bounded");
                error_count++;
                break;
            end
        end
    end
    req_valid <= 1'b0;
    check(bus_error == 2'b11, $sformatf("A1 write DECERR (got %b)", bus_error));
    $display("  [ok] A1 write completed with DECERR @%0t", $time);

    // A1b：读未路由段 → 同样强拆 → DECERR
    @(posedge clk);
    req_valid <= 1'b1;
    req_write <= 1'b0;
    req_addr  <= DEAD_ADDR;
    begin : single_rd
        int unsigned n;
        n = 0;
        forever begin
            @(posedge clk);
            n++;
            if (bus_tran_done) break;
            if (n >= MASTER_TIMEOUT + 8) req_valid <= 1'b0;
            if (n >= MASTER_TIMEOUT + 64) begin
                $display("  [FAIL] read not bounded");
                error_count++;
                break;
            end
        end
    end
    req_valid <= 1'b0;
    check(bus_error == 2'b11, $sformatf("A1b read DECERR (got %b)", bus_error));

    // A2/A3 由 bus_timeout_link_chk 实时断言检查（master_abort 事件打印即证据；
    // 每笔强拆后桥必须在 APB_TO_VAL+GRACE 拍内回 IDLE 且不被新事务叠加）
    repeat (20) @(posedge clk);

    if (error_count == 0)
        $display("=== BUS ABORT LINK TEST PASSED ===");
    else
        $display("=== BUS ABORT LINK TEST FAILED (%0d) ===", error_count);
    $finish;
end

// 看门狗
initial begin
    #10ms;
    $display("[WATCHDOG] test hung");
    $finish;
end

endmodule
