`include "./../SoC_Config.sv"
`include "./../RV32_inst_Define.sv"
`timescale 1ns / 1ps
module RISC_V_Core #(
    parameter ITCM_FILE = `ITCM_FILE,
    parameter DTCM_FILE = `DTCM_FILE,
    parameter ADDR_WIDTH = `ADDR_WIDTH,
    parameter DATA_WIDTH = `DATA_WIDTH,
    parameter REGFILE_NUM = `REGFILE_NUM,
    parameter REG_ADDR_WIDTH = `REG_ADDR_WIDTH,
    parameter CSR_ADDR_WIDTH = `CSR_ADDR_WIDTH,
    parameter ALIGN_BYTES = `ALIGN_BYTES,
    parameter ALIGN_WIDTH = `ALIGN_WIDTH,
    localparam BLOCK_SIZE_WIDTH = ADDR_WIDTH - `DEVICE_TAG_WIDTH
)(
    input   logic                       clk,
    input   logic                       rst_n,
    // from update
    input   logic                       itcm_wr_en,
    input   logic   [ADDR_WIDTH-1:0]    itcm_wr_addr,
    input   logic   [DATA_WIDTH-1:0]    itcm_wr_data,
    // from clint
    input   logic   [2*DATA_WIDTH-1:0]  mtime_shadow,
    input   logic                       software_int,
    input   logic                       timer_int,
    // from plic
    input   logic                       external_int,
    // from bus
    input   logic   [DATA_WIDTH-1:0]    bus_rdata,
    input   logic                       bus_tran_done,
    // to bus
    output  logic                       bus_transfer,
    output  logic                       bus_access_write,
    output  logic   [ADDR_WIDTH-1:0]    bus_access_addr,
    output  logic   [ALIGN_BYTES-1:0]   bus_access_wstrb,
    output  logic   [DATA_WIDTH-1:0]    bus_access_wdata
);

// Pipeline Ctrl
logic                       branch_jump_en;
logic   [ADDR_WIDTH-1:0]    branch_jump_addr;
// EX_MEM delayed branch signals (always declared; used by Pipeline_Ctrl when BRANCH_JUMP_DELAYED)
logic                       ex_mem_branch_jump_en;
logic   [ADDR_WIDTH-1:0]    ex_mem_branch_jump_addr;
logic                       trap_jump;
logic   [ADDR_WIDTH-1:0]    trap_jump_addr;
logic   [1:0]               priv_mode;
logic                       load_use_flag;
logic                       mem_access_ready;
logic                       mul_div_ready;

logic   [DATA_WIDTH-2:0]    exception_code_if;
logic   [DATA_WIDTH-2:0]    exception_code_id;
logic   [DATA_WIDTH-2:0]    exception_code_ex;
logic   [DATA_WIDTH-2:0]    exception_code_mem;
logic   [DATA_WIDTH-1:0]    exception_val_if;
logic   [DATA_WIDTH-1:0]    exception_val_id;
logic   [DATA_WIDTH-1:0]    exception_val_ex;
logic   [DATA_WIDTH-1:0]    exception_val_mem;
logic                       pc_stall;
logic                       ctrl_jump_en;
logic   [ADDR_WIDTH-1:0]    ctrl_jump_addr;
logic                       if_id_stall;
logic                       if_id_flush;
logic                       id_ex_stall;
logic                       id_ex_flush;
logic                       ex_mem_stall;
logic                       ex_mem_flush;
logic                       mem_wb_stall;
logic                       mem_wb_flush;
logic   [ADDR_WIDTH-1:0]    exception_inst_addr;
logic                       exception_trap;
logic   [DATA_WIDTH-2:0]    exception_code;
logic   [DATA_WIDTH-1:0]    exception_val;
logic   [ADDR_WIDTH-1:0]    next_inst_addr;

// Data_Hazard
logic   [DATA_WIDTH-1:0]    alu_op1_from_id_ex;
logic   [DATA_WIDTH-1:0]    alu_op2_from_id_ex;
logic   [DATA_WIDTH-1:0]    alu_op1_forward;
logic   [DATA_WIDTH-1:0]    alu_op2_forward;
logic   [DATA_WIDTH-1:0]    wr_mem_data_temp;
logic   [DATA_WIDTH-1:0]    rs2_data_ex;

//RegFile
logic                       wr_reg_en;
logic   [REG_ADDR_WIDTH-1:0]rd_rs1_addr;
logic   [REG_ADDR_WIDTH-1:0]rd_rs2_addr;
logic   [DATA_WIDTH-1:0]    rd_rs1_data;
logic   [DATA_WIDTH-1:0]    rd_rs2_data;
logic   [REG_ADDR_WIDTH-1:0]wr_reg_addr;
logic   [DATA_WIDTH-1:0]    wr_reg_data;

// IF
(*MAX_FANOUT =32*)logic   [ADDR_WIDTH-1:0]    pc;
(*MAX_FANOUT =32*)logic   [ADDR_WIDTH-1:0]    inst_addr_if;   // 当前指令地址（延迟一拍的 pc）
logic   [DATA_WIDTH-1:0]    inst;
logic                       predict_taken_if;
logic   [ADDR_WIDTH-1:0]    predict_target_if;


// ID
logic   [ADDR_WIDTH-1:0]    inst_addr_id;
logic   [DATA_WIDTH-1:0]    inst_id;
logic                       predict_taken_id;
logic   [ADDR_WIDTH-1:0]    predict_target_id;
logic   [DATA_WIDTH-1:0]    alu_op1_id;
logic   [DATA_WIDTH-1:0]    alu_op2_id;
logic   [DATA_WIDTH-1:0]    imm_id;
logic                       access_en_id;
logic                       access_wr_id;
logic                       wr_reg_en_id;
logic                       access_csr_en_id;
logic   [CSR_ADDR_WIDTH-1:0]csr_addr_id;

// EX
(*MAX_FANOUT =32*)logic   [ADDR_WIDTH-1:0]    inst_addr_ex;
logic   [DATA_WIDTH-1:0]    inst_ex;
logic                       predict_taken_ex;
logic   [ADDR_WIDTH-1:0]    predict_target_ex;
logic   [DATA_WIDTH-1:0]    imm_ex;
logic                       access_en_ex;
logic                       access_wr_ex;
logic   [ADDR_WIDTH-1:0]    mem_addr_ex;
logic   [2:0]               rd_mem_func3_ex;
logic   [DATA_WIDTH-1:0]    wr_mem_data_ex;
logic   [ALIGN_BYTES-1:0]   wr_mem_mask_ex;
logic                       wr_reg_en_ex;
logic   [REG_ADDR_WIDTH-1:0]wr_reg_addr_ex;
logic   [DATA_WIDTH-1:0]    wr_reg_data_ex;

logic   [REG_ADDR_WIDTH-1:0]rd_rs1_addr_ex;
logic   [REG_ADDR_WIDTH-1:0]rd_rs2_addr_ex;
logic                       wfi_req;
logic                       mret_req;

logic                       is_fence_i;
logic                       branch_taken;
logic   [ADDR_WIDTH-1:0]    branch_target;
logic   [1:0]               branch_inst_type;
logic                       branch_req;
logic                       branch_predict_success;
logic                       push_ras;
logic                       pop_ras;


// Mul_Div
logic                       mul_div_en;
logic   [2:0]               mul_div_func3;
logic   [DATA_WIDTH-1:0]    result_mul_div;
logic                       mul_div_valid;

//CSR
logic                       access_csr_en;
logic   [CSR_ADDR_WIDTH-1:0]csr_addr;
logic   [DATA_WIDTH-1:0]    rd_csr_data;
logic   [DATA_WIDTH-1:0]    wr_csr_data;
logic                       illegal_inst_csr;

// MEM
logic   [ADDR_WIDTH-1:0]    inst_addr_mem;
logic   [DATA_WIDTH-1:0]    inst_mem;
logic                       wr_reg_en_mem;
logic   [REG_ADDR_WIDTH-1:0]wr_reg_addr_mem;
logic   [DATA_WIDTH-1:0]    wr_reg_data_from_ex_mem;
logic   [DATA_WIDTH-1:0]    wr_reg_data_mem;
logic                       access_en;
logic   [ADDR_WIDTH-1:0]    access_addr;
logic                       access_wr;
// logic   [DATA_WIDTH-1:0]    access_wr_data;
// logic   [ALIGN_BYTES-1:0]   access_wr_mask;


logic   [DATA_WIDTH-1:0]    rd_dtcm_data;
logic   [2:0]               rd_mem_func3;
logic   [DATA_WIDTH-1:0]    wr_mem_data;
logic   [ALIGN_BYTES-1:0]   wr_mem_mask;
logic                       dtcm_sel;
logic                       bus_sel;


// WB
logic   [ADDR_WIDTH-1:0]    inst_addr_wb;
logic   [DATA_WIDTH-1:0]    inst_wb;

Pipeline_Ctrl #(
    .ADDR_WIDTH(ADDR_WIDTH),
    .DATA_WIDTH(DATA_WIDTH)
)u_Pipeline_Ctrl(
    .branch_jump_en      	(branch_jump_en       ),
    .branch_jump_addr    	(branch_jump_addr     ),
    .ex_mem_branch_jump_en (ex_mem_branch_jump_en),
    .ex_mem_branch_jump_addr(ex_mem_branch_jump_addr),
    .trap_jump           	(trap_jump            ),
    .trap_jump_addr      	(trap_jump_addr       ),
    .priv_mode           	(priv_mode            ),
    .load_use_flag       	(load_use_flag        ),
    .mem_access_ready    	(mem_access_ready     ),
    .mul_div_ready       	(mul_div_ready        ),
    .inst_addr_if        	(inst_addr_if         ),
    .inst_addr_id        	(inst_addr_id         ),
    .inst_addr_ex        	(inst_addr_ex         ),
    .inst_addr_mem       	(inst_addr_mem        ),
    .exception_code_if   	(exception_code_if    ),
    .exception_code_id   	(exception_code_id    ),
    .exception_code_ex   	(exception_code_ex    ),
    .exception_code_mem  	(exception_code_mem   ),
    .exception_val_if    	(exception_val_if     ),
    .exception_val_id    	(exception_val_id     ),
    .exception_val_ex    	(exception_val_ex     ),
    .exception_val_mem   	(exception_val_mem    ),
    .pc_stall            	(pc_stall             ),
    .ctrl_jump_en        	(ctrl_jump_en         ),
    .ctrl_jump_addr      	(ctrl_jump_addr       ),
    .if_id_stall         	(if_id_stall          ),
    .if_id_flush         	(if_id_flush          ),
    .id_ex_stall         	(id_ex_stall          ),
    .id_ex_flush         	(id_ex_flush          ),
    .ex_mem_stall        	(ex_mem_stall         ),
    .ex_mem_flush        	(ex_mem_flush         ),
    .mem_wb_stall        	(mem_wb_stall         ),
    .mem_wb_flush        	(mem_wb_flush         ),
    .exception_inst_addr 	(exception_inst_addr  ),
    .exception_trap      	(exception_trap       ),
    .exception_code      	(exception_code       ),
    .exception_val       	(exception_val        ),
    .next_inst_addr      	(next_inst_addr       )
);

Data_Hazard_Forward #(
    .ADDR_WIDTH     	(ADDR_WIDTH),
    .DATA_WIDTH     	(DATA_WIDTH),
    .REG_ADDR_WIDTH 	(REG_ADDR_WIDTH)
)u_Data_Hazard_Forward(
    .access_en_id       	(access_en_id       ),
    .access_wr_id       	(access_wr_id       ),
    .rd_rs1_addr_id     	(rd_rs1_addr        ),
    .rd_rs2_addr_id     	(rd_rs2_addr        ),
    .wr_reg_en_ex       	(wr_reg_en_ex       ),
    .rd_rs1_addr_ex     	(rd_rs1_addr_ex     ),
    .rd_rs2_addr_ex     	(rd_rs2_addr_ex     ),
    .wr_reg_addr_ex     	(wr_reg_addr_ex     ),
    .access_en_ex       	(access_en_ex       ),
    .access_wr_ex       	(access_wr_ex       ),
    .access_en_mem      	(access_en          ),
    .access_wr_mem      	(access_wr          ),
    .wr_reg_en_mem      	(wr_reg_en_mem      ),
    .wr_reg_addr_mem    	(wr_reg_addr_mem    ),
    .wr_reg_en_wb       	(wr_reg_en          ),
    .wr_reg_addr_wb     	(wr_reg_addr        ),
    .alu_op1_from_id_ex 	(alu_op1_from_id_ex ),
    .alu_op2_from_id_ex 	(alu_op2_from_id_ex ),
    .rd_rs2_data_ex     	(rs2_data_ex        ),
    .wr_reg_data_mem    	(wr_reg_data_mem    ),
    .wr_reg_data_wb     	(wr_reg_data        ),
    .bus_sel                (bus_sel            ),
    .bus_done               (bus_tran_done      ),
    .mem_access_ready       (mem_access_ready   ),
    .mem_addr_ex            (mem_addr_ex        ),
    .load_use_flag      	(load_use_flag      ),
    .alu_op1_o          	(alu_op1_forward    ),
    .alu_op2_o          	(alu_op2_forward    ),
    .wr_mem_data_temp   	(wr_mem_data_temp   )
);

Dynamic_Branch_Predictor #(
    .ADDR_WIDTH     (ADDR_WIDTH ),
    .DATA_WIDTH     (DATA_WIDTH ),
    .ALIGN_WIDTH    (ALIGN_WIDTH),
    .BTB_ENTRIES    (256),
    .PHT_ENTRIES    (128),
    .RAS_DEPTH      (8)
)u_Dynamic_Branch_Predictor(
    .clk             (clk            ),
    .rst_n           (rst_n          ),
    .is_fence_i      (is_fence_i     ),
    .stall           (pc_stall       ),
    .pc              (inst_addr_if   ),
    .branch_pc       (inst_addr_ex   ),
    .branch_taken    (branch_taken   ),
    .branch_target   (branch_target  ),  
    .branch_req      (branch_req     ),
    .branch_predict_success(branch_predict_success),
    .branch_inst_type(branch_inst_type),
    .push_ras        (push_ras       ),
    .pop_ras         (pop_ras        ),
    .predict_taken   (predict_taken_if),
    .predict_target  (predict_target_if)
);

PC_counter #(
    .ADDR_WIDTH(ADDR_WIDTH)
)u_PC_counter(
    .clk            (clk),
    .rst_n          (rst_n),
    .jump_en        (ctrl_jump_en),
    .jump_addr      (ctrl_jump_addr),
    .predict_taken  (predict_taken_if),
    .predict_target (predict_target_if),
    .stall          (pc_stall),
    .pc             (pc),               // 下一条指令地址，给 BootROM/ITCM 读地址
    .exception_code (exception_code_if),
    .exception_val  (exception_val_if),
    .inst_addr_o    (inst_addr_if)      // 当前指令地址，给流水线
);

// 指令来源 MUX（选择信号基于 inst_addr_if = 当前取出的指令地址）
logic [DATA_WIDTH-1:0]    bootrom_inst;
logic [DATA_WIDTH-1:0]    itcm_inst;
logic                     bootrom_sel;
logic                     itcm_sel;

assign bootrom_sel = (inst_addr_if[DATA_WIDTH-1:BLOCK_SIZE_WIDTH] == `BOOT_BASE_TAG);
assign itcm_sel    = (inst_addr_if[DATA_WIDTH-1:BLOCK_SIZE_WIDTH] == `ITCM_BASE_TAG);

BootROM #(
    .MROM_DEPTH     (`MROM_DEPTH),
    .ADDR_WIDTH     (ADDR_WIDTH),
    .DATA_WIDTH     (DATA_WIDTH),
    .ALIGN_WIDTH    (ALIGN_WIDTH)
)u_BootROM(
    .clk            (clk),
    .rst_n          (rst_n),
    .inst_addr      (pc),               // 提前一拍送地址
    .inst_o         (bootrom_inst)      // 同步读，下一拍输出
);

ITCM #(
    .ITCM_FILE      (ITCM_FILE),
    .ITCM_DEPTH     (`ITCM_DEPTH),
    .ADDR_WIDTH     (ADDR_WIDTH),
    .DATA_WIDTH     (DATA_WIDTH),
    .ALIGN_BYTES    (ALIGN_BYTES),
    .ALIGN_WIDTH    (ALIGN_WIDTH)
)u_ITCM(
    .clk            (clk),
    .rst_n          (rst_n),
    .itcm_wr_en     (itcm_wr_en),
    .itcm_wr_addr   (itcm_wr_addr),
    .itcm_wr_data   (itcm_wr_data),
    .inst_addr      (pc),               // 提前一拍送地址
    .inst_o         (itcm_inst)         // 同步读，下一拍输出
);

// 指令选择：BootROM → ITCM → NOP（非本地地址，未来走总线取指时扩展）
assign inst = bootrom_sel ? bootrom_inst :
              itcm_sel    ? itcm_inst    :
              `INST_NOP;

IF_ID #(
    .ADDR_WIDTH         (ADDR_WIDTH),
    .DATA_WIDTH         (DATA_WIDTH)
)u_IF_ID(
    .clk                (clk),
    .rst_n              (rst_n),
    .stall              (if_id_stall),
    .flush              (if_id_flush),
    .inst_addr_i        (inst_addr_if),     // 当前指令地址（延迟一拍的 pc）
    .inst_i             (inst),
    .predict_taken_i    (predict_taken_if),
    .predict_target_i   (predict_target_if),
    .inst_addr_o        (inst_addr_id),
    .inst_o             (inst_id),
    .predict_taken_o    (predict_taken_id),
    .predict_target_o   (predict_target_id)
);  

Decoder #(
    .ADDR_WIDTH     (ADDR_WIDTH),
    .DATA_WIDTH     (DATA_WIDTH),
    .REG_ADDR_WIDTH (REG_ADDR_WIDTH),
    .CSR_ADDR_WIDTH (CSR_ADDR_WIDTH)
)u_Decoder(
    .inst_addr      (inst_addr_id),
    .inst           (inst_id),
    .rd_rs1_addr    (rd_rs1_addr),
    .rd_rs2_addr    (rd_rs2_addr),
    .priv_mode      (priv_mode),
    .rd_rs1_data    (rd_rs1_data),
    .rd_rs2_data    (rd_rs2_data),
    .wr_reg_en      (wr_reg_en_id),
    .alu_op1        (alu_op1_id),
    .alu_op2        (alu_op2_id),
    .imm            (imm_id),
    .access_wr      (access_wr_id),
    .access_en      (access_en_id),
    .access_csr_en  (access_csr_en_id),
    .csr_addr       (csr_addr_id),
    .exception_code (exception_code_id),
    .exception_val  (exception_val_id)
);

RegFile #(
    .DATA_WIDTH     (DATA_WIDTH),
    .REG_ADDR_WIDTH (REG_ADDR_WIDTH),
    .REGFILE_NUM    (REGFILE_NUM)
)u_RegFile( 
    .clk            (clk),
    .rst_n          (rst_n),
    .rd_rs1_addr    (rd_rs1_addr),
    .rd_rs2_addr    (rd_rs2_addr),
    .rd_rs1_data    (rd_rs1_data),
    .rd_rs2_data    (rd_rs2_data),
    .wr_reg_en      (wr_reg_en),
    .wr_reg_addr    (wr_reg_addr),
    .wr_reg_data    (wr_reg_data)
);

ID_EX #(
    .ADDR_WIDTH     (ADDR_WIDTH),
    .DATA_WIDTH     (DATA_WIDTH),
    .CSR_ADDR_WIDTH (CSR_ADDR_WIDTH)
)u_ID_EX( 
    .clk            (clk),
    .rst_n          (rst_n),
    .stall          (id_ex_stall),
    .flush          (id_ex_flush),
    .inst_addr_i    (inst_addr_id),
    .inst_i         (inst_id),
    .predict_taken_i(predict_taken_id),
    .predict_target_i(predict_target_id),
    .alu_op1_i      (alu_op1_id),
    .alu_op2_i      (alu_op2_id),
    .imm_i          (imm_id),
    .rs2_data_i     (rd_rs2_data),
    .wr_reg_en_i    (wr_reg_en_id),
    .access_wr_i    (access_wr_id),
    .access_en_i    (access_en_id),
    .access_csr_en_i(access_csr_en_id),
    .csr_addr_i     (csr_addr_id),
    .rd_rs1_addr_i  (rd_rs1_addr),
    .rd_rs2_addr_i  (rd_rs2_addr),
    .inst_addr_o    (inst_addr_ex),
    .inst_o         (inst_ex),
    .predict_taken_o(predict_taken_ex),
    .predict_target_o(predict_target_ex),
    .alu_op1_o      (alu_op1_from_id_ex),
    .alu_op2_o      (alu_op2_from_id_ex),
    .imm_o          (imm_ex),
    .rs2_data_o     (rs2_data_ex),
    .wr_reg_en_o    (wr_reg_en_ex),
    .access_wr_o    (access_wr_ex),
    .access_en_o    (access_en_ex),
    .access_csr_en_o(access_csr_en),
    .csr_addr_o     (csr_addr),
    .rd_rs1_addr_o  (rd_rs1_addr_ex),
    .rd_rs2_addr_o  (rd_rs2_addr_ex)
);

Executer #(
    .ADDR_WIDTH     	(ADDR_WIDTH    ),
    .DATA_WIDTH     	(DATA_WIDTH    ),
    .REG_ADDR_WIDTH 	(REG_ADDR_WIDTH),
    .CSR_ADDR_WIDTH 	(CSR_ADDR_WIDTH),
    .ALIGN_BYTES    	(ALIGN_BYTES   ),
    .ALIGN_WIDTH    	(ALIGN_WIDTH   )
)u_Executer(
    .inst_addr        	(inst_addr_ex       ),
    .inst             	(inst_ex            ),
    .imm              	(imm_ex             ),
    .predict_taken    	(predict_taken_ex   ),
    .predict_target	    (predict_target_ex  ),
    .rd_csr_data      	(rd_csr_data        ),
    .illegal_inst_csr   (illegal_inst_csr   ),
    .alu_op1          	(alu_op1_forward    ),
    .alu_op2          	(alu_op2_forward    ),
    .wr_mem_data_temp 	(wr_mem_data_temp   ),
    .mul_div_valid    	(mul_div_valid      ),
    .result_mul_div   	(result_mul_div     ),
    .wr_reg_data_mem  	(wr_reg_data_mem    ),
    .wr_reg_data_wb   	(wr_reg_data        ),
    .branch_jump_en     (branch_jump_en     ),
    .branch_jump_addr   (branch_jump_addr   ),
    .exception_code  	(exception_code_ex  ),
    .exception_val   	(exception_val_ex   ),
    .mul_div_en       	(mul_div_en         ),
    .mul_div_func3    	(mul_div_func3      ),
    .mem_addr         	(mem_addr_ex        ),
    .wr_mem_data      	(wr_mem_data_ex     ),
    .wr_mem_mask      	(wr_mem_mask_ex     ),
    .rd_mem_func3     	(rd_mem_func3_ex    ),
    .wr_reg_addr      	(wr_reg_addr_ex     ),
    .wr_reg_data      	(wr_reg_data_ex     ),
    .wr_csr_data      	(wr_csr_data        ),
    .wfi_req            (wfi_req            ),
    .mret_req           (mret_req           ),
    .is_fence_i         (is_fence_i         ),
    .branch_taken       (branch_taken       ),
    .branch_target      (branch_target      ),
    .branch_inst_type   (branch_inst_type   ),
    .branch_req         (branch_req         ),
    .branch_predict_success(branch_predict_success),
    .push_ras           (push_ras           ),
    .pop_ras            (pop_ras            )
);

mul_div #(
    .DATA_WIDTH     	(DATA_WIDTH),
    .REG_ADDR_WIDTH 	(REG_ADDR_WIDTH)
)u_mul_div(
    .clk         	(clk            ),
    .rst_n       	(rst_n     ),
    .enable      	(mul_div_en     ),
    .rd_rs1_addr 	(rd_rs1_addr_ex ),
    .rd_rs2_addr 	(rd_rs2_addr_ex ),
    .wr_rd_addr  	(wr_reg_addr_ex ),
    .func3_i     	(mul_div_func3  ),
    .a_i         	(alu_op1_forward),
    .b_i         	(alu_op2_forward),
    .result_o    	(result_mul_div ),
    .data_valid  	(mul_div_valid  ),
    .ready       	(mul_div_ready  )
);

CSR_Reg_Access #(
    .ADDR_WIDTH     (ADDR_WIDTH),
    .DATA_WIDTH     (DATA_WIDTH),
    .CSR_ADDR_WIDTH (CSR_ADDR_WIDTH)
)u_CSR_Reg_Access(
    .clk            	(clk                ),
    .rst_n          	(rst_n         ),
    .access_csr_en      (access_csr_en      ),
    .csr_addr       	(csr_addr           ),
    .wr_csr_data    	(wr_csr_data        ),
    .rd_csr_data    	(rd_csr_data        ),
    .exception_inst_addr(exception_inst_addr),
    .next_inst_addr 	(next_inst_addr     ),
    .wfi_req        	(wfi_req            ),
    .mret_req       	(mret_req           ),
    .exception_trap 	(exception_trap     ),
    .exception_code 	(exception_code     ),
    .exception_val  	(exception_val      ),
    .external_int   	(external_int       ),
    .software_int   	(software_int       ),
    .timer_int      	(timer_int          ),
    .mtime_shadow   	(mtime_shadow       ),
    .illegal_inst_csr   (illegal_inst_csr   ),
    .priv_mode      	(priv_mode          ),
    .trap_jump      	(trap_jump          ),
    .trap_jump_addr 	(trap_jump_addr     )
);

EX_MEM #(
    .ADDR_WIDTH     (ADDR_WIDTH),
    .DATA_WIDTH     (DATA_WIDTH),
    .REG_ADDR_WIDTH (REG_ADDR_WIDTH),
    .ALIGN_BYTES    (ALIGN_BYTES)
)u_EX_MEM(
    .clk            (clk),
    .rst_n          (rst_n),
    .stall          (ex_mem_stall),
    .flush          (ex_mem_flush),
    .inst_addr_i    (inst_addr_ex),
    .inst_i         (inst_ex),
    .wr_reg_en_i    (wr_reg_en_ex),
    .wr_reg_addr_i  (wr_reg_addr_ex),
    .wr_reg_data_i  (wr_reg_data_ex),
    .access_en_i    (access_en_ex),
    .access_wr_i    (access_wr_ex),
    .mem_addr_i     (mem_addr_ex),
    .rd_mem_func3_i (rd_mem_func3_ex),
    .wr_mem_data_i  (wr_mem_data_ex),
    .wr_mem_mask_i  (wr_mem_mask_ex),
    .branch_jump_en_i  (branch_jump_en),
    .branch_jump_addr_i(branch_jump_addr),
    .inst_addr_o    (inst_addr_mem),
    .inst_o         (inst_mem),
    .access_en_o    (access_en),
    .access_wr_o    (access_wr),
    .mem_addr_o     (access_addr),
    .rd_mem_func3_o (rd_mem_func3),
    .wr_mem_data_o  (wr_mem_data),
    .wr_mem_mask_o  (wr_mem_mask),
    .branch_jump_en_o  (ex_mem_branch_jump_en),
    .branch_jump_addr_o(ex_mem_branch_jump_addr),
    .wr_reg_en_o    (wr_reg_en_mem),
    .wr_reg_addr_o  (wr_reg_addr_mem),
    .wr_reg_data_o  (wr_reg_data_from_ex_mem)
);

Mem_Access #(
    .ADDR_WIDTH (ADDR_WIDTH),
    .DATA_WIDTH (DATA_WIDTH)
)u_Mem_Access(
    .clk                        (clk),
    .rst_n                      (rst_n),
    .access_addr                (access_addr),
    .access_en                  (access_en),
    .access_wr                  (access_wr),
    .bus_tran_done              (bus_tran_done),
    .rd_dtcm_data               (rd_dtcm_data),
    .rd_bus_data                (bus_rdata),
    .rd_mem_func3               (rd_mem_func3),
    .wr_reg_data_from_ex_mem    (wr_reg_data_from_ex_mem),
    .dtcm_sel                   (dtcm_sel),
    .bus_sel                    (bus_sel),
    .mem_access_ready           (mem_access_ready),
    .exception_code             (exception_code_mem),
    .exception_val              (exception_val_mem),
    .wr_reg_data                (wr_reg_data_mem)
);


DTCM #(
    .DTCM_FILE   (DTCM_FILE),
    .DTCM_DEPTH  (`DTCM_DEPTH),
    .ADDR_WIDTH  (ADDR_WIDTH),
    .DATA_WIDTH  (DATA_WIDTH),
    .ALIGN_WIDTH (ALIGN_WIDTH),
    .ALIGN_BYTES (ALIGN_BYTES)
)u_DTCM(
    .clk        (clk),
    .rst_n      (rst_n),
    .access_addr(access_addr),
    .wr_en      (access_wr && dtcm_sel),
    .wr_data    (wr_mem_data),
    .wr_mask    (wr_mem_mask),
    .rd_data    (rd_dtcm_data)
);

MEM_WB #(
    .ADDR_WIDTH     (ADDR_WIDTH),
    .DATA_WIDTH     (DATA_WIDTH),
    .REG_ADDR_WIDTH (REG_ADDR_WIDTH)
)u_MEM_WB(
    .clk            (clk),
    .rst_n          (rst_n),
    .stall          (mem_wb_stall),
    .flush          (mem_wb_flush),
    .inst_addr_i    (inst_addr_mem),
    .inst_i         (inst_mem),
    .wr_reg_en_i    (wr_reg_en_mem),
    .wr_reg_addr_i  (wr_reg_addr_mem),
    .wr_reg_data_i  (wr_reg_data_mem),
    .inst_o         (inst_wb),
    .inst_addr_o    (inst_addr_wb),
    .wr_reg_en_o    (wr_reg_en),
    .wr_reg_addr_o  (wr_reg_addr),
    .wr_reg_data_o  (wr_reg_data)
);

assign bus_transfer   = access_en_ex && 
                        mem_addr_ex[ADDR_WIDTH-1:BLOCK_SIZE_WIDTH] >= `BUS_BASE_ADDR
                        && ~(ex_mem_flush || ex_mem_stall);
assign bus_access_write  = access_wr_ex;
assign bus_access_wdata  = wr_mem_data_ex;
assign bus_access_addr  = mem_addr_ex;
assign bus_access_wstrb  = wr_mem_mask_ex;

endmodule
