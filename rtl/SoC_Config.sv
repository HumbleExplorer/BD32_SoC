// =============================================================================
// SoC_Config.sv — BD32 SoC 全局配置
// =============================================================================
// 使用方式：
//   ModelSim 仿真：不定义 XILINX，默认 DIRECT_LOAD（从 .mem 加载）
//   Vivado 综合：  定义 XILINX（由 Vivado 自动注入），强制 UART 下载模式
//   Vivado 仿真：  定义 XILINX + SIMULATION
// =============================================================================

// ============================================================
// 1. 基础参数（所有环境通用）
// ============================================================
`define ADDR_WIDTH 32
`define DATA_WIDTH 32
`define REGFILE_NUM 32
`define REG_ADDR_WIDTH 5
`define CSR_ADDR_WIDTH 12
`define ALIGN_BYTES 4
`define ALIGN_WIDTH 2
`define DEVICE_TAG_WIDTH 16

`define ITCM_DEPTH 16*1024
`define DTCM_DEPTH 16*1024
`define MROM_DEPTH 1*1024

`define ITCM_LENGTH (`ITCM_DEPTH * `ALIGN_BYTES)  // 16K×4 = 64KB
`define DTCM_LENGTH (`DTCM_DEPTH * `ALIGN_BYTES)

// ============================================================
// 2. 功能开关
// ============================================================
// 3 级流水线乘法器（默认状态机 4 拍，启用后 3 拍）
`define MULT_PIPELINE

// RISC-V Debug Module（JTAG TAP + DM，Spec 0.13）
// 仿真：+define+BD32_DEBUG_EN  综合：Vivado Settings 添加
`define BD32_DEBUG_EN

// 硬件断点 trigger 数量（mcontrol，多路）
`define TRIGGER_NUM 4

// 访存地址快速加法（减少 EX 阶段关键路径）
// `define ADDR_GEN_FAST

// Load→Store 前递转发 forward_C（增加扇出，改善 Load-Store 停顿）
// `define FORWARD_C_EN

// APB 延迟响应模拟
// `define APB_ACCESS_DELAYED_DONE

// ============================================================
// 3. 测试模式（互斥，仿真时通过 +define+ 注入）
// ============================================================
// `define CORE_TEST               // riscv-tests / custom_asm 裸核测试
// `define CUSTOM_ASM              // 配合 CORE_TEST 使用自定义汇编
// `define BUS_TIMEOUT_TEST        // 总线超时异常测试
// `define RESET_REDOWNLOAD_TEST   // 复位后重新下载测试
// `define GPIO_SIM                // GPIO 仿真模型
// `define TIMER_SIM               // Timer 仿真模型

// ============================================================
// 4. 加载模式
// ============================================================
// DIRECT_LOAD = 从 .mem 文件初始化 BRAM（仿真快速加载）
// 关闭后走 BootROM → UART 下载路径（FPGA 板级运行）
//
// 注意：Vivado 综合时强制关闭（见下方 `ifdef XILINX）
// 注意：BUS_TIMEOUT_TEST / RESET_REDOWNLOAD_TEST 强制关闭
`define DIRECT_LOAD

`ifdef BUS_TIMEOUT_TEST
    `undef DIRECT_LOAD
`endif
`ifdef RESET_REDOWNLOAD_TEST
    `undef DIRECT_LOAD
`endif

// ============================================================
// 5. 环境适配（路径 + 存储类型）
// ============================================================
`ifdef XILINX
    // --- Vivado 环境 ---
    `define TCM_Reg_or_BRAM "BRAM"
    `define BOOT_PATH "../../../../../test_data/soc/"
    `ifdef SIMULATION
        // Vivado 行为仿真
        `define PATH "../../../../../test_data/soc/c/"
        `define DISPLAY_INST_WAVE
    `else
        // Vivado 综合 → 强制 UART 下载（BRAM 不预加载程序）
        `undef DIRECT_LOAD
        `define SYNTHESIS
        `define PATH "../soc/c/"
    `endif
`else
    // --- ModelSim 环境 ---
    `define TCM_Reg_or_BRAM "Reg"
    `define BOOT_PATH "../../test_data/soc/"
    `define PATH "../../test_data/soc/c/"
    `define DISPLAY_INST_WAVE
    // `define DEBUG
`endif

// CORE_TEST 模式下 PATH 指向裸核测试用例
`ifdef CORE_TEST
    `ifdef CUSTOM_ASM
        `undef PATH
        `define PATH "../../test_data/custom_asm/"
    `else
        `undef PATH
        `define PATH "../../test_data/riscv-tests/"
    `endif
`endif

// ============================================================
// 6. 加载文件选择
// ============================================================
`ifdef DIRECT_LOAD
    // 直接加载：.mem 文件初始化 ITCM/DTCM
    `define ITCM_FILE "coremark_o2_itcm.mem"
    `define DTCM_FILE "coremark_o2_dtcm.mem"
`else
    // UART 下载：BootROM 等待串口发送 .uartbin
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

`define MROM_FILE "mrom.dat"

// ============================================================
// 7. 地址映射
// ============================================================
// --- AXI Interconnect 路由（地址高 4 位 [31:28] 译码）---
`define AXI_FLASH_BASE_ADDR    32'h9000_0000  // [31:28]=4'h9/A, 512MB
`define AXI_DDR_BASE_ADDR      32'hB000_0000  // [31:28]=4'hB/C, 512MB
`define AXI_APB_BRIDGE_BASE    32'hE000_0000  // [31:28]=4'hE/F, 512MB

// --- AXI-APB Bridge 从机映射（[31:16] 匹配，每个从机 64KB）---
`define APB_SLAVE_ADDR_WIDTH   16
`define APB_NUM_SLAVES         16

`define APB_CLINT_BASE_ADDR    32'hF200_0000  // PSEL[0]
`define APB_PLIC_BASE_ADDR     32'hFC00_0000  // PSEL[1]
`define APB_GPIO_BASE_ADDR     32'hE000_0000  // PSEL[2]
`define APB_UART_BASE_ADDR     32'hE001_0000  // PSEL[3]
`define APB_TIMER_BASE_ADDR    32'hE002_0000  // PSEL[4]
`define APB_SPI_BASE_ADDR      32'hE003_0000  // PSEL[5]
`define APB_I2C_BASE_ADDR      32'hE004_0000  // PSEL[6]

// --- 总线阈值 ---
`define BUS_BASE_ADDR  `DEVICE_TAG_WIDTH'h8000  // 高16位 >= 此值走 AXI

// AXI 超时（时钟周期）：80MHz 下 1024 周期 ≈ 12.8μs
`define BUS_TIMEOUT  1024

// --- 16 位设备标签（快速地址译码用）---
`define BOOT_BASE_TAG  `DEVICE_TAG_WIDTH'h0000
`define CLINT_BASE_TAG `DEVICE_TAG_WIDTH'hF200
`define PLIC_BASE_TAG  `DEVICE_TAG_WIDTH'hFC00
`define GPIO_BASE_TAG  `DEVICE_TAG_WIDTH'hE000
`define UART_BASE_TAG  `DEVICE_TAG_WIDTH'hE001
`define TIMER_BASE_TAG `DEVICE_TAG_WIDTH'hE002
`define SPI_BASE_TAG   `DEVICE_TAG_WIDTH'hE003
`define I2C_BASE_TAG   `DEVICE_TAG_WIDTH'hE004

`ifdef CORE_TEST
    `define ITCM_BASE_TAG `DEVICE_TAG_WIDTH'h0001
    `define DTCM_BASE_TAG `DEVICE_TAG_WIDTH'h0001
`else
    `define ITCM_BASE_TAG `DEVICE_TAG_WIDTH'h0001
    `define DTCM_BASE_TAG `DEVICE_TAG_WIDTH'h0002
`endif

// --- 外部存储容量 ---
`define FLASH_LENGTH 128*1024*1024/8       // 128Mbit / 8 = 16MB
`define DDR_LENGTH   256*1024*1024*16/8    // 256M × 16bit = 512MB
`define MAX_SIZE ((`DDR_LENGTH > `FLASH_LENGTH) ? `DDR_LENGTH : `FLASH_LENGTH)

// ============================================================
// 8. 外设数量
// ============================================================
`define GPIO_NUM 5
`define TIMER_NUM 1
`define TIMER_CHANNEL_NUM 4

// ============================================================
// 9. AXI 总线位宽
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
`define AXI_STRB_WIDTH   `ALIGN_BYTES
