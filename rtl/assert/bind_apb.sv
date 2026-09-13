// =============================================================================
// bind_apb.sv — APB 从机协议断言（bind 挂载，综合不可见）
// =============================================================================
// 覆盖 5 个 APB 从机：CLINT / PLIC / apb_uart / apb_timer / apb_gpio。
// 只加入编译全部从机的 filelist（soc_test / debug_test）；
// 外设单项测试只编译各自子集，bind 目标缺失会报错，勿加入。
// 断言（ARM APB 协议）：
//   1) PENABLE 必须随 PSEL（无 select 不得 enable）
//   2) SETUP→ACCESS：PSEL 且未 PENABLE 次拍必起 PENABLE（仍选中时）
//   3) 传输等待期（PSEL&&PENABLE&&!PREADY）地址/写控制稳定
//   4) 写传输 PWDATA 稳定
//   5) 传输有界完成（64 拍内 PREADY）
// =============================================================================
`ifndef SYNTHESIS

module apb_slave_chk #(
    parameter string NAME = "APB",
    parameter int    AW   = 32,
    parameter int    DW   = 32
)(
    input logic               PCLK,
    input logic               PRESETn,
    input logic               PSEL,
    input logic               PENABLE,
    input logic               PWRITE,
    input logic               PREADY,
    input logic [AW-1:0]      PADDR,
    input logic [DW-1:0]      PWDATA
);
    // 1) PENABLE 无 PSEL 视为协议错
    a_pen_nopsel: assert property (
        @(posedge PCLK) disable iff (!PRESETn)
        (PENABLE |-> PSEL))
        else $error("[SVA][APB-%s] PENABLE 无 PSEL", NAME);
    // 2) SETUP→ACCESS：选中且未使能，次拍使能或取消选中
    a_setup_access: assert property (
        @(posedge PCLK) disable iff (!PRESETn)
        ((PSEL && !PENABLE) |=> (PENABLE || !PSEL)))
        else $error("[SVA][APB-%s] SETUP 态停留超 1 拍", NAME);
    // 3) 等待期（PENABLE 且 !PREADY）地址/写控制稳定
    property p_addr_stable;
        @(posedge PCLK) disable iff (!PRESETn)
        ((PSEL && PENABLE && !PREADY) |=> (PSEL && $stable(PADDR) && $stable(PWRITE)));
    endproperty
    a_addr_stable: assert property (p_addr_stable)
        else $error("[SVA][APB-%s] 等待期地址/写控制漂移", NAME);
    // 4) 写传输等待期 PWDATA 稳定
    property p_wdata_stable;
        @(posedge PCLK) disable iff (!PRESETn)
        ((PSEL && PENABLE && PWRITE && !PREADY) |=> $stable(PWDATA));
    endproperty
    a_wdata_stable: assert property (p_wdata_stable)
        else $error("[SVA][APB-%s] 写传输等待期数据漂移", NAME);
    // 5) 传输有界完成：PENABLE 起 64 拍内必 PREADY
    a_bounded_done: assert property (
        @(posedge PCLK) disable iff (!PRESETn)
        ((PSEL && PENABLE && !PREADY) |-> ##[1:64] PREADY))
        else $error("[SVA][APB-%s] 传输超 64 拍未完成", NAME);

endmodule

// 逐从机 bind——端口连接表达式在目标作用域解析，同名直连即透传
bind CLINT     apb_slave_chk #(.NAME("CLINT"), .AW(32), .DW(32)) u_chk_apb_clint (
    .PCLK(PCLK), .PRESETn(PRESETn), .PSEL(PSEL), .PENABLE(PENABLE),
    .PWRITE(PWRITE), .PREADY(PREADY), .PADDR(PADDR), .PWDATA(PWDATA));
bind apb_uart  apb_slave_chk #(.NAME("UART"),  .AW(32), .DW(32)) u_chk_apb_uart (
    .PCLK(PCLK), .PRESETn(PRESETn), .PSEL(PSEL), .PENABLE(PENABLE),
    .PWRITE(PWRITE), .PREADY(PREADY), .PADDR(PADDR), .PWDATA(PWDATA));
bind apb_timer apb_slave_chk #(.NAME("TIMER"), .AW(32), .DW(32)) u_chk_apb_timer (
    .PCLK(PCLK), .PRESETn(PRESETn), .PSEL(PSEL), .PENABLE(PENABLE),
    .PWRITE(PWRITE), .PREADY(PREADY), .PADDR(PADDR), .PWDATA(PWDATA));
bind apb_gpio  apb_slave_chk #(.NAME("GPIO"),  .AW(32), .DW(32)) u_chk_apb_gpio (
    .PCLK(PCLK), .PRESETn(PRESETn), .PSEL(PSEL), .PENABLE(PENABLE),
    .PWRITE(PWRITE), .PREADY(PREADY), .PADDR(PADDR), .PWDATA(PWDATA));
bind PLIC      apb_slave_chk #(.NAME("PLIC"),  .AW(32), .DW(32)) u_chk_apb_plic (
    .PCLK(PCLK), .PRESETn(PRESETn), .PSEL(PSEL), .PENABLE(PENABLE),
    .PWRITE(PWRITE), .PREADY(PREADY), .PADDR(PADDR), .PWDATA(PWDATA));

`endif // SYNTHESIS
