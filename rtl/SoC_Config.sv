`define ADDR_WIDTH 32
`define DATA_WIDTH 32
`define REGFILE_NUM 32
`define REG_ADDR_WIDTH 5
`define CSR_ADDR_WIDTH 12
`define ALIGN_BYTES 4
`define ALIGN_WIDTH 2
`define BOOT_BASE_ADDR 16'h0000
`define ITCM_BASE_ADDR 16'h0001
`define DTCM_BASE_ADDR 16'h0002
`define CLINT_BASE_ADDR 16'h0200
`define PLIC_BASE_ADDR 16'h0C00
`define BUS_BASE_ADDR 16'h8000
`define GPIO_BASE_ADDR 16'h8000
`define UART_BASE_ADDR 16'h8001
`define SPI_BASE_ADDR 16'h8002
`define I2C_BASE_ADDR 16'h8003
`define TIMER_BASE_ADDR 16'h8004

`define FLASH_BASE_ADDR 16'h8200
`define FLASH_LENGTH 128*1024*1024/8//128Mbit/8=16MB
`define DDR_BASE_ADDR 16'h8400
`define DDR_LENGTH 256*1024*1024*16/8//256M*16bit=512MB
`define GPIO_NUM 2

// `define GPIO_SIM
`ifdef MODELSIM
    `define PATH "./test_data/"//vsim路径
    `define ITCM_DEPTH 16*1024//16K
    `define DTCM_DEPTH 16*1024//16K
`elsif XILINX
    `define PATH "../test_data/"//Vivado路径
    // `define PATH "D:/Desktop/RV32_SoC/Working/test_data/"//Vivado路径
    `define ITCM_DEPTH 8*1024//8K
    `define DTCM_DEPTH 8*1024//8K
`else
    `define PATH "./test_data/"
    `define ITCM_DEPTH 8*1024//8K
    `define DTCM_DEPTH 8*1024//8K
`endif
// `define PATH "./test_data/"
// `define ITCM_DEPTH 8*1024//8K
// `define DTCM_DEPTH 8*1024//8K

`define MROM_DEPTH 1*1024//1K


`define ITCM_LENGTH ITCM_DEPTH*ALIGN_BYTES// 8/16K*4B=32/64KB
`define DTCM_LENGTH DTCM_DEPTH*ALIGN_BYTES// 8/16K*4B=32/64KB

`define ITCM_FILE "test1.dat"
`define DTCM_FILE "story.dat"
`define MROM_FILE "mrom.dat"
// `define TCM_Reg_or_BRAM "BRAM"
`define TCM_Reg_or_BRAM "Reg"