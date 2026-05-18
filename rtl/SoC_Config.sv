`define ADDR_WIDTH 32
`define DATA_WIDTH 32
`define REGFILE_NUM 32
`define REG_ADDR_WIDTH 5
`define CSR_ADDR_WIDTH 12
`define ALIGN_BYTES 4
`define ALIGN_WIDTH 2
`define DEVICE_TAG_WIDTH 16


// ============================================================
// 分支跳转延迟1拍（EX_MEM锁存）— 时序优化
// ============================================================
// 启用后，EX阶段的 branch_jump_en/addr 先经 EX_MEM 寄存器，
// 下一拍再由 Pipeline_Ctrl 响应，切断 EX→PC 的长组合路径。
// 代价：预测失败多浪费1拍（3拍 vs 2拍），正确预测零开销。
// 注释下行则以原始方式（EX 直通）运行：
`define BRANCH_JUMP_DELAYED


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

// AXI-Lite 响应打拍：在 rsp_* 输出处插寄存器，切断 AXI Bus → CPU 长组合路径
// 增加 1 拍响应延迟，但大幅改善时序。Vivado 综合时启用。
`define AXI_LITE_DELAYED_DONE

// `define GPIO_SIM
// `define TIMER_SIM

// `define XILINX
// `define SIMULATION
`ifdef XILINX
    `ifdef SIMULATION
        `define PATH "../../../../../test_data/"
        `define ITCM_DEPTH 16*1024//8K
        `define DTCM_DEPTH 16*1024//8K
        `ifdef DIRECT_LOAD
            `define ITCM_FILE "custom/step2_irq_pwm_itcm.mem"
            `define DTCM_FILE "custom/step2_irq_pwm_dtcm.mem"
            `define ITCM_DIRECT_LOAD
        `else
            `define ITCM_FILE "custom/all_asm.uartbin"
            `define DTCM_FILE "custom/all_asm.uartbin"
        `endif
        `define TCM_Reg_or_BRAM "BRAM"
    `else
        `define PATH "../test_data/"//Vivado路径
        `define ITCM_DEPTH 16*1024//8K
        `define DTCM_DEPTH 16*1024//8K
        `define ITCM_FILE "test2_full.dat"
        `define DTCM_FILE "welcome_text_full.dat"
        `define TCM_Reg_or_BRAM "BRAM"
    `endif
`else
    `define DIRECT_LOAD  // 注释掉则走 UART 下载
    `define PATH "../../test_data/"
    `define ITCM_DEPTH 16*1024//8K
    `define DTCM_DEPTH 16*1024//8K
    `ifdef DIRECT_LOAD
        `define ITCM_FILE "custom/step2_irq_pwm_itcm.mem"
        `define DTCM_FILE "custom/step2_irq_pwm_dtcm.mem"
        `define ITCM_DIRECT_LOAD
    `else
        `define ITCM_FILE "custom/all_asm.uartbin"
        `define DTCM_FILE "custom/all_asm.uartbin"
    `endif
    `define TCM_Reg_or_BRAM "Reg"
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
    `define ITCM_DIRECT_LOAD
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
