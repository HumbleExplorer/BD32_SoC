// ==============================================================================
// SoC_Config.sv — BD32 SoC 全局配置（条件编译类：开关/测试模式/加载/环境/路径）
// ==============================================================================
// 带保护宏：BD32_Pkg.sv 会反向包含本文件（包内常量引用位宽 define），其余文件
// 的 `include 由此变为无操作。地址映射/存储几何/外设数量/AXI 位宽等纯常量
// 已迁入 rtl/pkg/BD32_Pkg.sv 的 bd32_pkg，不在此定义。
// =============================================================================
// 使用方式：
//   ModelSim 仿真：不定义 XILINX，默认 DIRECT_LOAD（从 .mem 加载）
//   Vivado 综合：  定义 XILINX（由 Vivado 自动注入），强制 UART 下载模式
//   Vivado 仿真：  定义 XILINX + SIMULATION
// =============================================================================

`ifndef SOC_CONFIG_INCLUDED
`define SOC_CONFIG_INCLUDED

// ============================================================
// 1. 基础位宽参数（所有环境通用；存储深度已迁入 bd32_pkg）
// ============================================================
`define ADDR_WIDTH 32
`define DATA_WIDTH 32
`define REGFILE_NUM 32
`define REG_ADDR_WIDTH 5
`define CSR_ADDR_WIDTH 12
`define ALIGN_BYTES 4
`define ALIGN_WIDTH 2
`define DEVICE_TAG_WIDTH 16

// ============================================================
// 2. 功能开关
// ============================================================
// 3 级流水线乘法器（默认状态机 4 拍，启用后 3 拍）
`define MULT_PIPELINE

// RISC-V Debug Module（JTAG TAP + DM，Spec 0.13）
// 默认开启；如需关闭可注释本行
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
    // 直接加载：.mem 文件初始化 ITCM/DTCM（默认 breathing，
    // 可用 +define+ITCM_FILE="xxx.mem" / +define+DTCM_FILE="xxx.mem" 覆盖）
    `ifndef ITCM_FILE
        `define ITCM_FILE "breathing_itcm.mem"
    `endif
    `ifndef DTCM_FILE
        `define DTCM_FILE "breathing_dtcm.mem"
    `endif
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

`endif // SOC_CONFIG_INCLUDED
