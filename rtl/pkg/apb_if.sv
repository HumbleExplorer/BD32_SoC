// =============================================================================
// apb_if.sv — AMBA APB3 接口定义
// =============================================================================
// 用法：
//   主机侧（APB_Master / 桥 / BFM）端口声明 `apb_if.master m`；
//   从机侧（外设）端口声明 `apb_if.slave s`；
//   监视/断言用 `apb_if.mon`。
//   互联对上游是 slave 视角、对下游是 master 视角（APB_Interconnect）。
//   接口实例必须先于使用它的模块编译（filelist 首行 pkg glob 已保证）。
//   位宽默认 32/32，与本 SoC 全局位宽一致；例化处可传参覆盖。
// =============================================================================
interface apb_if #(
    parameter integer ADDR_WIDTH = 32,
    parameter integer DATA_WIDTH = 32
)();
    localparam integer STRB_WIDTH = DATA_WIDTH/8;

    // APB 命令信号（主机 → 从机）
    logic [ADDR_WIDTH-1:0]  paddr;
    logic                   psel;
    logic                   penable;
    logic                   pwrite;
    logic [STRB_WIDTH-1:0]  pstrb;
    logic [DATA_WIDTH-1:0]  pwdata;
    // APB 返回信号（从机 → 主机）
    logic [DATA_WIDTH-1:0]  prdata;
    logic                   pready;
    logic                   pslverr;

    modport master (
        output paddr, psel, penable, pwrite, pstrb, pwdata,
        input  prdata, pready, pslverr
    );

    modport slave (
        input  paddr, psel, penable, pwrite, pstrb, pwdata,
        output prdata, pready, pslverr
    );

    modport mon (
        input  paddr, psel, penable, pwrite, pstrb, pwdata,
               prdata, pready, pslverr
    );

endinterface
