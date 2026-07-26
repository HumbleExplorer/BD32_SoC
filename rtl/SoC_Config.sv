`define ADDR_WIDTH 32
`define DATA_WIDTH 32
`define REGFILE_NUM 32
`define REG_ADDR_WIDTH 5
`define CSR_ADDR_WIDTH 12
`define ALIGN_BYTES 4
`define ALIGN_WIDTH 2
`define DEVICE_TAG_WIDTH 16

// 取消注释下行启用 3 级流水线乘法器（默认状态机，4 拍一结果）
`define MULT_PIPELINE


// 访存地址快速加法：用 12 位加法+高位条件调整代替 32 位 CARRY4×8 链，
// 减少 mem_addr 关键路径的时序压力。启用后可改善 EX 阶段时序。
// 取消注释下行以启用：
// `define ADDR_GEN_FAST

// Load→Store 前递转发（forward_C）
// 启用后：Load 后紧跟 Store 时不需停顿（通过 forward_C 转发 wr_reg_data_mem）
// 关闭后：Load→Store 会产生 load-use stall（转发回退到 forward_B）
// 关闭可减少 wr_reg_data_mem 扇出，改善时序
// 取消注释下行启用：
// `define FORWARD_C_EN

// `define APB_ACCESS_DELAYED_DONE
// `define GPIO_SIM
// `define TIMER_SIM

// 复位后重新下载测试：模拟「下载程序→复位→再次下载」场景
// 启用后自动关闭 DIRECT_LOAD，走 UART 下载路径，使用 blink.uartbin
// `define RESET_REDOWNLOAD_TEST

// 总线访问超时测试：模拟「Timer 从机挂死 (apb_pready[4]=0)」场景
// 启用后自动关闭 DIRECT_LOAD，走 UART 下载路径，使用 bus_timeout.uartbin
// CPU 向 Timer 写寄存器 → 总线无响应 → BUS_TIMEOUT 后触发 store access
// fault (mcause=7)，验证 AXI 超时保护 + 异常上报链路
// `define BUS_TIMEOUT_TEST

`define DIRECT_LOAD  // 注释掉则走 UART 下载
// `define CUSTOM_ASM
// `define XILINX
// `define SIMULATION
// `define BUS_TIMEOUT_TEST  // 由 run_bus_timeout_test.do 的 +define+ 注入
// RESET_REDOWNLOAD_TEST / BUS_TIMEOUT_TEST 需要 UART 下载路径，强制关闭 DIRECT_LOAD
`ifdef RESET_REDOWNLOAD_TEST
    `undef DIRECT_LOAD
`endif


`ifdef DIRECT_LOAD
    `ifdef CORE_TEST
        
        `ifdef CUSTOM_ASM
            `define PATH "../../test_data/custom_asm/"
        `else
            `define PATH "../../test_data/riscv-tests/"
        `endif
    `else
        `define PATH "../../test_data/soc/c/"
    `endif
    `define ITCM_FILE "coremark_o2_itcm.mem"
    `define DTCM_FILE "coremark_o2_dtcm.mem"
`else
    `define PATH "../../test_data/soc/c/"
    `ifdef BUS_TIMEOUT_TEST
        `define ITCM_FILE "bus_timeout.uartbin"
        `define DTCM_FILE "bus_timeout.uartbin"
    `elsif RESET_REDOWNLOAD_TEST
        `define ITCM_FILE "blink.uartbin"
        `define DTCM_FILE "blink.uartbin"
    `else
        `define ITCM_FILE "breathing.uartbin"
        `define DTCM_FILE "breathing.uartbin"
    `endif
`endif

`ifdef XILINX
    `define BOOT_PATH "../../../../../test_data/soc/"
    `ifdef SIMULATION
        `define PATH "../../../../../test_data/soc/c/"
        `define ITCM_DEPTH 16*1024
        `define DTCM_DEPTH 16*1024
        `define TCM_Reg_or_BRAM "BRAM"
        `define DISPLAY_INST_WAVE
    `else
        `define SYNTHESIS
        `define PATH "../soc/c/"//Vivado路径
        `define ITCM_DEPTH 16*1024
        `define DTCM_DEPTH 16*1024
        `define TCM_Reg_or_BRAM "BRAM"
    `endif
`else
    // `define DEBUG
    `define ITCM_DEPTH 16*1024
    `define DTCM_DEPTH 16*1024
    `define BOOT_PATH "../../test_data/soc/"
    `define TCM_Reg_or_BRAM "Reg"
    `define DISPLAY_INST_WAVE
`endif


`define MROM_DEPTH 1*1024//1K

`define ITCM_LENGTH (`ITCM_DEPTH*`ALIGN_BYTES)// 8/16K*4B=32/64KB
`define DTCM_LENGTH (`DTCM_DEPTH*`ALIGN_BYTES)// 8/16K*4B=32/64KB
// ============================================================
// AXI 地址映射（2026-04-24 修订）
// ============================================================
// AXI_Interconnect 1→4 路由（地址高4位 [31:28] 译码）
// `define AXI_MROM_BASE_ADDR     32'h8000_0000  // [31:28]=4'h8, 256MB
`define AXI_FLASH_BASE_ADDR    32'h9000_0000  // [31:28]=4'h9/A, 512MB
`define AXI_DDR_BASE_ADDR      32'hB000_0000  // [31:28]=4'hB/C, 512MB
`define AXI_APB_BRIDGE_BASE    32'hE000_0000  // [31:28]=4'hE/F, 512MB

// AXI-APB Bridge 内部地址映射（PSEL 解码）
// 每个 APB 从机占 64KB 地址空间，基址按 [31:16] 匹配
`define APB_SLAVE_ADDR_WIDTH   16             // [15:0] 为从机内部偏移
`define APB_NUM_SLAVES         16             // 可配置 APB 从机数量

// APB 从机基址（32位完整地址，Bridge 内部用 [31:16] 匹配）
`define APB_CLINT_BASE_ADDR    32'hF200_0000  // PSEL[0]
`define APB_PLIC_BASE_ADDR     32'hFC00_0000  // PSEL[1]
`define APB_GPIO_BASE_ADDR     32'hE000_0000  // PSEL[2]
`define APB_UART_BASE_ADDR     32'hE001_0000  // PSEL[3]
`define APB_TIMER_BASE_ADDR    32'hE002_0000  // PSEL[4]
`define APB_SPI_BASE_ADDR      32'hE003_0000  // PSEL[5]
`define APB_I2C_BASE_ADDR      32'hE004_0000  // PSEL[6]

// 总线地址阈值（16位标签）：地址高16位 >= 此值则走 AXI 总线
`define BUS_BASE_ADDR  `DEVICE_TAG_WIDTH'h8000

// AXI 总线访问超时阈值（时钟周期数）：从机若在此周期内无响应，
// AXI_Lite_Master 强制完成事务并返回 DECERR，触发 load/store access fault，
// 防止从机挂死导致 CPU 永久卡死。80MHz 下 1024 周期 ≈ 12.8us。
`define BUS_TIMEOUT  1024

// 兼容旧代码的 16 位设备标签（APB 内部偏移计算用）
`define CLINT_BASE_TAG  `DEVICE_TAG_WIDTH'hF200
`define PLIC_BASE_TAG   `DEVICE_TAG_WIDTH'hFC00
`define GPIO_BASE_TAG   `DEVICE_TAG_WIDTH'hE000
`define UART_BASE_TAG   `DEVICE_TAG_WIDTH'hE001
`define TIMER_BASE_TAG  `DEVICE_TAG_WIDTH'hE002
`define SPI_BASE_TAG    `DEVICE_TAG_WIDTH'hE003
`define I2C_BASE_TAG    `DEVICE_TAG_WIDTH'hE004

// CPU 启动地址
`define BOOT_BASE_TAG  `DEVICE_TAG_WIDTH'h0000

// ITCM / DTCM
`ifdef CORE_TEST
    `define ITCM_BASE_TAG `DEVICE_TAG_WIDTH'h0001
    `define DTCM_BASE_TAG `DEVICE_TAG_WIDTH'h0001
`else
    `define ITCM_BASE_TAG  `DEVICE_TAG_WIDTH'h0001
    `define DTCM_BASE_TAG  `DEVICE_TAG_WIDTH'h0002
`endif

// Flash / DDR（AXI 地址空间，当前留空由 err_slave 返回 0）
`define FLASH_LENGTH 128*1024*1024/8  // 128Mbit/8=16MB
`define DDR_LENGTH   256*1024*1024*16/8  // 256M*16bit=512MB

`define MAX_SIZE ((`DDR_LENGTH > `FLASH_LENGTH)? `DDR_LENGTH : `FLASH_LENGTH)
`define GPIO_NUM 5
`define TIMER_CHANNEL_NUM 4
`define TIMER_NUM 1

`define MROM_FILE "mrom.dat"


// ============================================================
// AXI 总线配置 - BIU 架构（2026-04-24）
// CPU 通过 AXI_Lite_Master → AXI_Interconnect → 各 AXI 从机
// 端口保留 AXI-Full 信号，内部按 AXI-Lite 运行
// ============================================================
`define AXI_ID_WIDTH     4
`define AXI_LEN_WIDTH    8
`define AXI_SIZE_WIDTH   3
`define AXI_BURST_WIDTH  2
`define AXI_CACHE_WIDTH  4
`define AXI_PROT_WIDTH   3
`define AXI_QOS_WIDTH    4
`define AXI_REGION_WIDTH 4
`define AXI_RESP_WIDTH   2
`define AXI_STRB_WIDTH   `ALIGN_BYTES  // 4 bytes
