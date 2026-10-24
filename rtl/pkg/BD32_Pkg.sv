// ==============================================================================
// BD32_Pkg.sv — BD32 共享常量包
// ==============================================================================
// 包含 SoC_Config.sv（带保护宏，重复包含为无操作）以引用基础位宽 define。
// ==============================================================================
`include "./../SoC_Config.sv"

// ===============================================================================
// 用法：需要引用包内常量的模块，在 module 声明之前写 `import bd32_pkg::*;`
// （文件级 import 才能覆盖端口声明；模块内 import 只覆盖模块体）。
// 编译顺序：包文件必须先于所有 import 它的模块编译（各 filelist 首行已保证）。
// =============================================================================

package bd32_pkg;

// I type inst
localparam logic [6:0] INST_TYPE_I     = 7'b0010011;
localparam logic [2:0] INST_ADDI       = 3'b000;
localparam logic [2:0] INST_SLTI       = 3'b010;
localparam logic [2:0] INST_SLTIU      = 3'b011;
localparam logic [2:0] INST_XORI       = 3'b100;
localparam logic [2:0] INST_ORI        = 3'b110;
localparam logic [2:0] INST_ANDI       = 3'b111;
localparam logic [2:0] INST_SLLI       = 3'b001;
localparam logic [2:0] INST_SRI        = 3'b101;

// L type inst
localparam logic [6:0] INST_TYPE_L     = 7'b0000011;
localparam logic [2:0] INST_LB         = 3'b000;
localparam logic [2:0] INST_LH         = 3'b001;
localparam logic [2:0] INST_LW         = 3'b010;
localparam logic [2:0] INST_LBU        = 3'b100;
localparam logic [2:0] INST_LHU        = 3'b101;

// S type inst
localparam logic [6:0] INST_TYPE_S     = 7'b0100011;
localparam logic [2:0] INST_SB         = 3'b000;
localparam logic [2:0] INST_SH         = 3'b001;
localparam logic [2:0] INST_SW         = 3'b010;

// R and M type inst
localparam logic [6:0] INST_TYPE_R_M   = 7'b0110011;

// R type inst
localparam logic [2:0] INST_ADD_SUB    = 3'b000;
localparam logic [2:0] INST_SLL        = 3'b001;
localparam logic [2:0] INST_SLT        = 3'b010;
localparam logic [2:0] INST_SLTU       = 3'b011;
localparam logic [2:0] INST_XOR        = 3'b100;
localparam logic [2:0] INST_SR         = 3'b101;
localparam logic [2:0] INST_OR         = 3'b110;
localparam logic [2:0] INST_AND        = 3'b111;

// M type inst
localparam logic [2:0] INST_MUL        = 3'b000;
localparam logic [2:0] INST_MULH       = 3'b001;
localparam logic [2:0] INST_MULHSU     = 3'b010;
localparam logic [2:0] INST_MULHU      = 3'b011;
localparam logic [2:0] INST_DIV        = 3'b100;
localparam logic [2:0] INST_DIVU       = 3'b101;
localparam logic [2:0] INST_REM        = 3'b110;
localparam logic [2:0] INST_REMU       = 3'b111;

// J type inst
localparam logic [6:0] INST_JAL        = 7'b1101111;
localparam logic [6:0] INST_JALR       = 7'b1100111;

localparam logic [6:0] INST_LUI        = 7'b0110111;
localparam logic [6:0] INST_AUIPC      = 7'b0010111;
localparam logic [31:0] INST_NOP       = 32'h00000013;

// FENCE
localparam logic [6:0] INST_FENCE      = 7'b0001111;

// B type inst
localparam logic [6:0] INST_TYPE_B     = 7'b1100011;
localparam logic [2:0] INST_BEQ        = 3'b000;
localparam logic [2:0] INST_BNE        = 3'b001;
localparam logic [2:0] INST_BLT        = 3'b100;
localparam logic [2:0] INST_BGE        = 3'b101;
localparam logic [2:0] INST_BLTU       = 3'b110;
localparam logic [2:0] INST_BGEU       = 3'b111;

// CSR inst
localparam logic [6:0] INST_SYSTEM     = 7'b1110011;
localparam logic [2:0] INST_PRIV       = 3'b000;  // ECALL EBREAK MRET WFI
localparam logic [2:0] INST_CSRRW      = 3'b001;
localparam logic [2:0] INST_CSRRS      = 3'b010;
localparam logic [2:0] INST_CSRRC      = 3'b011;
localparam logic [2:0] INST_CSRRWI     = 3'b101;
localparam logic [2:0] INST_CSRRSI     = 3'b110;
localparam logic [2:0] INST_CSRRCI     = 3'b111;
localparam logic [11:0] INST_ECALL     = 12'h000;
localparam logic [11:0] INST_EBREAK    = 12'h001;
localparam logic [11:0] INST_MRET      = 12'h302;
localparam logic [11:0] INST_WFI       = 12'h105;

// ============================================================================
// 存储几何（原 SoC_Config 第 1 节存储段）
// ============================================================================
localparam int unsigned ITCM_DEPTH  = 16*1024;                       // 16K 字
localparam int unsigned DTCM_DEPTH  = 16*1024;                       // 16K 字
localparam int unsigned MROM_DEPTH  = 1*1024;                        // 1K 字
localparam int unsigned ITCM_LENGTH = ITCM_DEPTH * `ALIGN_BYTES;     // 16K×4 = 64KB
localparam int unsigned DTCM_LENGTH = DTCM_DEPTH * `ALIGN_BYTES;     // 16K×4 = 64KB

// ============================================================================
// 地址映射（原 SoC_Config 第 7 节）
// ============================================================================
// --- AXI Interconnect 路由（地址高 4 位 [31:28] 译码）---
localparam logic [31:0] AXI_FLASH_BASE_ADDR = 32'h9000_0000;  // [31:28]=4'h9/A, 512MB
localparam logic [31:0] AXI_DDR_BASE_ADDR   = 32'hB000_0000;  // [31:28]=4'hB/C, 512MB
localparam logic [31:0] AXI_APB_BRIDGE_BASE = 32'hE000_0000;  // [31:28]=4'hE/F, 512MB

// --- AXI-APB Bridge 从机映射（[31:16] 匹配，每个从机 64KB）---
localparam int unsigned APB_SLAVE_ADDR_WIDTH = 16;
localparam int unsigned APB_NUM_SLAVES       = 16;

localparam logic [31:0] APB_CLINT_BASE_ADDR = 32'hF200_0000;  // PSEL[0]
localparam logic [31:0] APB_PLIC_BASE_ADDR  = 32'hFC00_0000;  // PSEL[1]
localparam logic [31:0] APB_GPIO_BASE_ADDR  = 32'hE000_0000;  // PSEL[2]
localparam logic [31:0] APB_UART_BASE_ADDR  = 32'hE001_0000;  // PSEL[3]
localparam logic [31:0] APB_TIMER_BASE_ADDR = 32'hE002_0000;  // PSEL[4]
localparam logic [31:0] APB_SPI_BASE_ADDR   = 32'hE003_0000;  // PSEL[5]
localparam logic [31:0] APB_I2C_BASE_ADDR   = 32'hE004_0000;  // PSEL[6]

// --- 总线阈值 ---
localparam logic [`DEVICE_TAG_WIDTH-1:0] BUS_BASE_ADDR = `DEVICE_TAG_WIDTH'h8000;  // 高16位 >= 此值走 AXI

// AXI 超时（时钟周期）：50MHz 下 1024 周期 ≈ 20.48μs
// 形式验证（sby 定义 FORMAL）下缩小到 8：验证的是超时机制本身而非标定值，
// 且 BMC depth 30 可全程覆盖逃逸路径；PDR 无需归纳 16 位计数器关系
`ifdef FORMAL
localparam int unsigned BUS_TIMEOUT = 8;
`else
localparam int unsigned BUS_TIMEOUT = 1024;
`endif

// --- 16 位设备标签（快速地址译码用；位宽 = DEVICE_TAG_WIDTH）---
localparam logic [`DEVICE_TAG_WIDTH-1:0] BOOT_BASE_TAG  = `DEVICE_TAG_WIDTH'h0000;
localparam logic [`DEVICE_TAG_WIDTH-1:0] CLINT_BASE_TAG = `DEVICE_TAG_WIDTH'hF200;
localparam logic [`DEVICE_TAG_WIDTH-1:0] PLIC_BASE_TAG  = `DEVICE_TAG_WIDTH'hFC00;
localparam logic [`DEVICE_TAG_WIDTH-1:0] GPIO_BASE_TAG  = `DEVICE_TAG_WIDTH'hE000;
localparam logic [`DEVICE_TAG_WIDTH-1:0] UART_BASE_TAG  = `DEVICE_TAG_WIDTH'hE001;
localparam logic [`DEVICE_TAG_WIDTH-1:0] TIMER_BASE_TAG = `DEVICE_TAG_WIDTH'hE002;
localparam logic [`DEVICE_TAG_WIDTH-1:0] SPI_BASE_TAG   = `DEVICE_TAG_WIDTH'hE003;
localparam logic [`DEVICE_TAG_WIDTH-1:0] I2C_BASE_TAG   = `DEVICE_TAG_WIDTH'hE004;

`ifdef CORE_TEST
localparam logic [`DEVICE_TAG_WIDTH-1:0] ITCM_BASE_TAG = `DEVICE_TAG_WIDTH'h0001;
localparam logic [`DEVICE_TAG_WIDTH-1:0] DTCM_BASE_TAG = `DEVICE_TAG_WIDTH'h0001;
`else
localparam logic [`DEVICE_TAG_WIDTH-1:0] ITCM_BASE_TAG = `DEVICE_TAG_WIDTH'h0001;
localparam logic [`DEVICE_TAG_WIDTH-1:0] DTCM_BASE_TAG = `DEVICE_TAG_WIDTH'h0002;
`endif

// --- 外部存储容量 ---
localparam int unsigned FLASH_LENGTH = 128*1024*1024/8;      // 128Mbit / 8 = 16MB
localparam int unsigned DDR_LENGTH   = 256*1024*1024*16/8;   // 256M × 16bit = 512MB
localparam int unsigned MAX_SIZE     = (DDR_LENGTH > FLASH_LENGTH) ? DDR_LENGTH : FLASH_LENGTH;

// ============================================================================
// 外设数量（原 SoC_Config 第 8 节）
// ============================================================================
localparam int unsigned GPIO_NUM          = 5;
localparam int unsigned TIMER_NUM         = 1;
localparam int unsigned TIMER_CHANNEL_NUM = 4;

// ============================================================================
// AXI 总线位宽（原 SoC_Config 第 9 节）
// ============================================================================
localparam int unsigned AXI_ID_WIDTH     = 4;
localparam int unsigned AXI_LEN_WIDTH    = 8;
localparam int unsigned AXI_SIZE_WIDTH   = 3;
localparam int unsigned AXI_BURST_WIDTH  = 2;
localparam int unsigned AXI_CACHE_WIDTH  = 4;
localparam int unsigned AXI_PROT_WIDTH   = 3;
localparam int unsigned AXI_QOS_WIDTH    = 4;
localparam int unsigned AXI_REGION_WIDTH = 4;
localparam int unsigned AXI_RESP_WIDTH   = 2;
localparam int unsigned AXI_STRB_WIDTH   = `ALIGN_BYTES;

// ============================================================================
// CSR 地址（机器模式 + time；CSR_Reg_Access 译码用）
// ============================================================================
localparam logic [11:0] CSR_MSTATUS            = 12'h300;
localparam logic [11:0] CSR_MISA               = 12'h301;
localparam logic [11:0] CSR_MIE                = 12'h304;
localparam logic [11:0] CSR_MTVEC              = 12'h305;
localparam logic [11:0] CSR_MCOUNTINHIBIT      = 12'h320;
localparam logic [11:0] CSR_MSCRATCH           = 12'h340;
localparam logic [11:0] CSR_MEPC               = 12'h341;
localparam logic [11:0] CSR_MCAUSE             = 12'h342;
localparam logic [11:0] CSR_MTVAL              = 12'h343;
localparam logic [11:0] CSR_MIP                = 12'h344;
localparam logic [11:0] CSR_MCYCLE             = 12'hB00;
localparam logic [11:0] CSR_MINSTRET           = 12'hB02;
localparam logic [11:0] CSR_MCYCLEH            = 12'hB80;
localparam logic [11:0] CSR_MINSTRETH          = 12'hB82;
localparam logic [11:0] CSR_MCOUNTERCLR        = 12'hBC0;
localparam logic [11:0] CSR_TIME               = 12'hC01;
localparam logic [11:0] CSR_TIMEH              = 12'hC81;
localparam logic [11:0] CSR_MHPMCOUNTER3       = 12'hB03;
localparam logic [11:0] CSR_MHPMCOUNTER4       = 12'hB04;
localparam logic [11:0] CSR_MHPMCOUNTER5       = 12'hB05;
localparam logic [11:0] CSR_MHPMCOUNTER6       = 12'hB06;
localparam logic [11:0] CSR_MHPMCOUNTER7       = 12'hB07;
localparam logic [11:0] CSR_MHPMCOUNTER8       = 12'hB08;
localparam logic [11:0] CSR_MHPMCOUNTER9       = 12'hB09;
localparam logic [11:0] CSR_MHPMCOUNTER10      = 12'hB0A;
localparam logic [11:0] CSR_MHPMCOUNTER11      = 12'hB0B;
localparam logic [11:0] CSR_MHPMCOUNTER12      = 12'hB0C;
localparam logic [11:0] CSR_MHPMCOUNTER13      = 12'hB0D;
localparam logic [11:0] CSR_MHPMCOUNTER14      = 12'hB0E;
localparam logic [11:0] CSR_MHPMCOUNTER15      = 12'hB0F;
localparam logic [11:0] CSR_MHPMCOUNTER16      = 12'hB10;
localparam logic [11:0] CSR_MHPMCOUNTER17      = 12'hB11;
localparam logic [11:0] CSR_MHPMCOUNTER3H      = 12'hB83;
localparam logic [11:0] CSR_MHPMCOUNTER4H      = 12'hB84;
localparam logic [11:0] CSR_MHPMCOUNTER5H      = 12'hB85;
localparam logic [11:0] CSR_MHPMCOUNTER6H      = 12'hB86;
localparam logic [11:0] CSR_MHPMCOUNTER7H      = 12'hB87;
localparam logic [11:0] CSR_MHPMCOUNTER8H      = 12'hB88;
localparam logic [11:0] CSR_MHPMCOUNTER9H      = 12'hB89;
localparam logic [11:0] CSR_MHPMCOUNTER10H     = 12'hB8A;
localparam logic [11:0] CSR_MHPMCOUNTER11H     = 12'hB8B;
localparam logic [11:0] CSR_MHPMCOUNTER12H     = 12'hB8C;
localparam logic [11:0] CSR_MHPMCOUNTER13H     = 12'hB8D;
localparam logic [11:0] CSR_MHPMCOUNTER14H     = 12'hB8E;
localparam logic [11:0] CSR_MHPMCOUNTER15H     = 12'hB8F;
localparam logic [11:0] CSR_MHPMCOUNTER16H     = 12'hB90;
localparam logic [11:0] CSR_MHPMCOUNTER17H     = 12'hB91;

// ============================================================================
// 异常原因码（mcause[3:0]，bit31=0）/ 中断原因码（mcause[3:0]，bit31=1）
// 注意：同一编号在两 namespace 下语义不同（3=断点/MSI，7=Store 访错/MTI，
// 11=ECALL-M/MEI），使用时按 mcause[31] 区分。
// ============================================================================
localparam logic [3:0] EXC_INSN_ADDR_MISALIGNED   = 4'd0;
localparam logic [3:0] EXC_INSN_ACCESS_FAULT      = 4'd1;
localparam logic [3:0] EXC_ILLEGAL_INSN           = 4'd2;
localparam logic [3:0] EXC_BREAKPOINT             = 4'd3;
localparam logic [3:0] EXC_LOAD_ADDR_MISALIGNED   = 4'd4;
localparam logic [3:0] EXC_LOAD_ACCESS_FAULT      = 4'd5;
localparam logic [3:0] EXC_STORE_ADDR_MISALIGNED  = 4'd6;
localparam logic [3:0] EXC_STORE_ACCESS_FAULT     = 4'd7;
localparam logic [3:0] EXC_ECALL_UMODE            = 4'd8;
localparam logic [3:0] EXC_ECALL_HSMODE           = 4'd9;
localparam logic [3:0] EXC_ECALL_MMODE            = 4'd11;

localparam logic [3:0] INT_MSI                    = 4'd3;
localparam logic [3:0] INT_MTI                    = 4'd7;
localparam logic [3:0] INT_MEI                    = 4'd11;

endpackage
