// =============================================================================
// axi_if.sv — AXI4 接口定义（Full 信号，Lite 行为使用）
// =============================================================================
// 用法：
//   主机侧（Bus_Access 内 AXI_Lite_Master / BFM）端口声明 `axi_if.master m`；
//   从机侧（AXI_APB_Bridge / axi_err_slave）端口声明 `axi_if.slave s`；
//   互联对上游是 slave 视角、对下游是三个固定 master 视角
//   （AXI_Interconnect 的 m0/m1/m2）。
//   接口实例必须先于使用它的模块编译（filelist 首行 pkg glob 已保证），
//   且实例必须带 `()`。位宽默认 32/32/4/8，与本 SoC 全局配置一致。
// =============================================================================
interface axi_if #(
    parameter integer ADDR_WIDTH = 32,
    parameter integer DATA_WIDTH = 32,
    parameter integer ID_WIDTH   = 4,
    parameter integer LEN_WIDTH  = 8
)();
    localparam integer STRB_WIDTH = DATA_WIDTH/8;

    // 写地址通道（主机 → 从机）
    logic [ID_WIDTH-1:0]    awid;
    logic [ADDR_WIDTH-1:0]  awaddr;
    logic [LEN_WIDTH-1:0]   awlen;
    logic [2:0]             awsize;
    logic [1:0]             awburst;
    logic                   awlock;
    logic [3:0]             awcache;
    logic [2:0]             awprot;
    logic [3:0]             awqos;
    logic [3:0]             awregion;
    logic                   awvalid;
    logic                   awready;
    // 写数据通道（主机 → 从机）
    logic [DATA_WIDTH-1:0]  wdata;
    logic [STRB_WIDTH-1:0]  wstrb;
    logic                   wlast;
    logic                   wvalid;
    logic                   wready;
    // 写响应通道（从机 → 主机）
    logic [ID_WIDTH-1:0]    bid;
    logic [1:0]             bresp;
    logic                   bvalid;
    logic                   bready;
    // 读地址通道（主机 → 从机）
    logic [ID_WIDTH-1:0]    arid;
    logic [ADDR_WIDTH-1:0]  araddr;
    logic [LEN_WIDTH-1:0]   arlen;
    logic [2:0]             arsize;
    logic [1:0]             arburst;
    logic                   arlock;
    logic [3:0]             arcache;
    logic [2:0]             arprot;
    logic [3:0]             arqos;
    logic [3:0]             arregion;
    logic                   arvalid;
    logic                   arready;
    // 读数据通道（从机 → 主机）
    logic [ID_WIDTH-1:0]    rid;
    logic [DATA_WIDTH-1:0]  rdata;
    logic [1:0]             rresp;
    logic                   rlast;
    logic                   rvalid;
    logic                   rready;

    modport master (
        output awid, awaddr, awlen, awsize, awburst, awlock, awcache,
               awprot, awqos, awregion, awvalid,
        input  awready,
        output wdata, wstrb, wlast, wvalid,
        input  wready,
        input  bid, bresp, bvalid,
        output bready,
        output arid, araddr, arlen, arsize, arburst, arlock, arcache,
               arprot, arqos, arregion, arvalid,
        input  arready,
        input  rid, rdata, rresp, rlast, rvalid,
        output rready
    );

    modport slave (
        input  awid, awaddr, awlen, awsize, awburst, awlock, awcache,
               awprot, awqos, awregion, awvalid,
        output awready,
        input  wdata, wstrb, wlast, wvalid,
        output wready,
        output bid, bresp, bvalid,
        input  bready,
        input  arid, araddr, arlen, arsize, arburst, arlock, arcache,
               arprot, arqos, arregion, arvalid,
        output arready,
        output rid, rdata, rresp, rlast, rvalid,
        input  rready
    );

endinterface
