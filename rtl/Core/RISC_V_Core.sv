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
    // ITCM download
    input   logic                       itcm_download_en,
    input   logic   [ADDR_WIDTH-1:0]    itcm_download_addr,
    input   logic   [DATA_WIDTH-1:0]    itcm_download_data,
    // DTCM download
    input   logic                       dtcm_download_en,
    input   logic   [ADDR_WIDTH-1:0]    dtcm_download_addr,
    input   logic   [DATA_WIDTH-1:0]    dtcm_download_data,
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
`ifndef BRANCH_JUMP_DELAYED
logic                       branch_jump_en_ex;
logic   [ADDR_WIDTH-1:0]    branch_jump_addr_ex;
// EX_MEM delayed branch signals (always declared; used by Pipeline_Ctrl / Dynamic_Branch_Predictor when BRANCH_JUMP_DELAYED)
`else
logic                       branch_jump_en_mem;
logic   [ADDR_WIDTH-1:0]    branch_jump_addr_mem;
`endif
(* max_fanout = 32 *) logic                       trap_jump;
logic   [ADDR_WIDTH-1:0]    trap_jump_addr;
logic   [1:0]               priv_mode;
(* max_fanout = 32 *) logic                       load_use_flag;
logic                       mem_access_ready;
logic                       mul_div_ready;

logic   [DATA_WIDTH-2:0]    exception_code_if;
logic   [DATA_WIDTH-2:0]    exception_code_id;
logic   [DATA_WIDTH-2:0]    exception_code_ex;
logic   [DATA_WIDTH-1:0]    exception_val_if;
logic   [DATA_WIDTH-1:0]    exception_val_id;
logic   [DATA_WIDTH-1:0]    exception_val_ex;
(* max_fanout = 32 *) logic                       pc_stall;
logic                       ctrl_jump_en;
logic   [ADDR_WIDTH-1:0]    ctrl_jump_addr;
logic                       if_id_stall;
logic                       if_id_flush;
logic                       id_ex_stall;
logic                       id_ex_flush;
logic                       ex_mem_stall;
(* max_fanout = 32 *) logic                       ex_mem_flush;
logic                       mem_wb_stall;
logic                       mem_wb_flush;
logic   [ADDR_WIDTH-1:0]    exception_inst_addr;
(* max_fanout = 32 *) logic                       exception_trap;
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
logic                       is_fence_i_id;
logic   [1:0]               branch_inst_type_id;// 指令类型 (00:非跳转指令, 01:B, 10:JAL, 11:JALR)
logic                       branch_req_id;
logic                       push_ras_id;        // call
logic                       pop_ras_id;          // ret
logic   [ADDR_WIDTH-1:0]    jump_imm_id;
logic   [ADDR_WIDTH-1:0]    inst_addr_plus_4_id;
assign jump_imm_id          = inst_addr_id + imm_id;
assign inst_addr_plus_4_id  = inst_addr_id + 32'd4;

// EX
(*MAX_FANOUT =32*)logic   [ADDR_WIDTH-1:0]    inst_addr_ex;
logic   [DATA_WIDTH-1:0]    inst_ex;
logic                       predict_taken_ex;
logic   [ADDR_WIDTH-1:0]    predict_target_ex;
logic   [DATA_WIDTH-1:0]    imm_ex;
logic   [ADDR_WIDTH-1:0]    jump_imm_ex;
logic   [ADDR_WIDTH-1:0]    inst_addr_plus_4_ex;
logic                       access_en_ex;
logic                       access_wr_ex;
logic   [ADDR_WIDTH-1:0]    access_addr_ex;
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

logic                       is_fence_i_ex;
logic                       branch_taken_ex;
logic   [ADDR_WIDTH-1:0]    branch_target_ex;
logic   [1:0]               branch_inst_type_ex;
logic                       branch_req_ex;
`ifndef BRANCH_JUMP_DELAYED
logic                       branch_predict_success_ex;
`endif
logic                       push_ras_ex;
logic                       pop_ras_ex;



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
logic   [DATA_WIDTH-1:0]    wr_reg_data_mem;
logic   [DATA_WIDTH-1:0]    func3_expanded_data;
logic   [DATA_WIDTH-1:0]    wr_reg_selected_data_mem;   // MUX2 output: load data or ALU result
logic                       access_en_mem;                  // EX/MEM delayed, used by Data_Hazard_Forward
logic                       access_wr_mem;                  // EX/MEM delayed, used by Data_Hazard_Forward
`ifdef BRANCH_JUMP_DELAYED
logic                       is_fence_i_mem;
logic                       branch_taken_mem;
logic   [ADDR_WIDTH-1:0]    branch_target_mem;
logic                       branch_req_mem;
logic   [1:0]               branch_inst_type_mem;
logic                       branch_predict_success_mem;
logic                       push_ras_mem;
logic                       pop_ras_mem;
`endif
logic   [DATA_WIDTH-1:0]    rd_dtcm_data;
logic                       dtcm_sel;
logic                       bus_sel;
logic                       dtcm_rvalid;
logic                       bus_rvalid;
logic                       bus_rvalid_r1;
logic                       bus_rvalid_r2;
logic                       bus_ready_r;
// MEM/WB bypass for bus loads (wr_reg_en/addr from EX stage, bypassing EX/MEM)
logic                       wr_reg_selected_en_mem;
logic   [REG_ADDR_WIDTH-1:0]wr_reg_selected_addr_mem;


// WB
logic   [ADDR_WIDTH-1:0]    inst_addr_wb;
logic   [DATA_WIDTH-1:0]    inst_wb;
logic                       wr_reg_en_wb;
logic   [REG_ADDR_WIDTH-1:0]wr_reg_addr_wb;
logic   [DATA_WIDTH-1:0]    wr_reg_data_wb;

Pipeline_Ctrl #(
    .ADDR_WIDTH(ADDR_WIDTH),
    .DATA_WIDTH(DATA_WIDTH)
)u_Pipeline_Ctrl(
`ifdef BRANCH_JUMP_DELAYED
    .branch_jump_en      	(branch_jump_en_mem),
    .branch_jump_addr    	(branch_jump_addr_mem),
`else
    .branch_jump_en      	(branch_jump_en_ex    ),
    .branch_jump_addr    	(branch_jump_addr_ex  ),
`endif
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
    .exception_val_if    	(exception_val_if     ),
    .exception_val_id    	(exception_val_id     ),
    .exception_val_ex    	(exception_val_ex     ),
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
    .clk                    (clk),
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
    .access_en_mem      	(access_en_mem      ),
    .access_wr_mem      	(access_wr_mem      ),
    .wr_reg_en_mem      	(wr_reg_en_mem      ),
    .wr_reg_addr_mem    	(wr_reg_addr_mem    ),
    .wr_reg_en_wb       	(wr_reg_en_wb       ),
    .wr_reg_addr_wb     	(wr_reg_addr_wb     ),
    .alu_op1_from_id_ex 	(alu_op1_from_id_ex ),
    .alu_op2_from_id_ex 	(alu_op2_from_id_ex ),
    .rd_rs2_data_ex     	(rs2_data_ex        ),
    .wr_reg_data_mem    	(wr_reg_data_mem    ),
    .wr_reg_data_wb     	(wr_reg_data_wb     ),
    .bus_sel                (bus_sel            ),
    .bus_rvalid             (bus_rvalid_r1      ),
    .mem_access_ready       (mem_access_ready   ),
    .bus_ready_r            (bus_ready_r        ),
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
    .stall           (pc_stall       ),
    .pc              (inst_addr_if   ),
`ifdef BRANCH_JUMP_DELAYED
    .is_fence_i      (is_fence_i_mem ),
    .branch_pc       (inst_addr_mem  ),  // 从 EX_MEM 寄存器输出来（与 branch_taken 对齐）
    // 其他更新信号从 EX_MEM 寄存器输出取
    .branch_taken    (branch_taken_mem    ),
    .branch_target   (branch_target_mem   ),  
    .branch_req      (branch_req_mem      ),
    .branch_predict_success(branch_predict_success_mem),
    .branch_inst_type(branch_inst_type_mem),
    .push_ras        (push_ras_mem        ),
    .pop_ras         (pop_ras_mem         ),
`else
    .is_fence_i      (is_fence_i_ex  ),
    .branch_pc       (inst_addr_ex  ),  // 从 EX_MEM 寄存器输出来（与 branch_taken 对齐）
    .branch_taken    (branch_taken_ex   ),
    .branch_target   (branch_target_ex  ),  
    .branch_req      (branch_req_ex     ),
    .branch_predict_success(branch_predict_success_ex),
    .branch_inst_type(branch_inst_type_ex),
    .push_ras        (push_ras_ex       ),
    .pop_ras         (pop_ras_ex        ),
`endif
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
    .itcm_download_en     (itcm_download_en),
    .itcm_download_addr   (itcm_download_addr),
    .itcm_download_data   (itcm_download_data),
    .inst_addr      (pc),               // 提前一拍送地址
    .inst_o         (itcm_inst)         // 同步读，下一拍输出
);

// 指令选择：BootROM → ITCM → NOP（非本地地址，未来走总线取指时扩展）
`ifdef XILINX
assign inst = bootrom_sel ? bootrom_inst :
              itcm_sel    ? itcm_inst    :
              `INST_NOP;
`else
// 若取出的指令含不定态 X，替换为 NOP 防止 X 传播
assign inst = bootrom_sel ? ($isunknown(bootrom_inst) ? `INST_NOP : bootrom_inst) :
              itcm_sel    ? ($isunknown(itcm_inst)    ? `INST_NOP : itcm_inst)    :
              `INST_NOP;
`endif
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
    .is_fence_i     (is_fence_i_id),
    .branch_inst_type(branch_inst_type_id),
    .branch_req     (branch_req_id),
    .push_ras       (push_ras_id),
    .pop_ras        (pop_ras_id),
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
    .jump_imm_i     (jump_imm_id),
    .inst_addr_plus_4_i(inst_addr_plus_4_id),
    .rd_rs1_addr_i  (rd_rs1_addr),
    .rd_rs2_addr_i  (rd_rs2_addr),
    .wr_reg_en_i    (wr_reg_en_id),
    .access_wr_i    (access_wr_id),
    .access_en_i    (access_en_id),
    .access_csr_en_i(access_csr_en_id),
    .csr_addr_i     (csr_addr_id),
    .is_fence_i_i     (is_fence_i_id),
    .branch_inst_type_i(branch_inst_type_id),
    .branch_req_i   (branch_req_id),
    .push_ras_i     (push_ras_id),
    .pop_ras_i      (pop_ras_id),
    .inst_addr_o    (inst_addr_ex),
    .inst_o         (inst_ex),
    .predict_taken_o(predict_taken_ex),
    .predict_target_o(predict_target_ex),
    .alu_op1_o      (alu_op1_from_id_ex),
    .alu_op2_o      (alu_op2_from_id_ex),
    .imm_o          (imm_ex),
    .jump_imm_o     (jump_imm_ex),
    .inst_addr_plus_4_o(inst_addr_plus_4_ex),
    .rs2_data_o     (rs2_data_ex),
    .wr_reg_en_o    (wr_reg_en_ex),
    .access_wr_o    (access_wr_ex),
    .access_en_o    (access_en_ex),
    .access_csr_en_o(access_csr_en),
    .csr_addr_o     (csr_addr),
    .is_fence_i_o   (is_fence_i_ex),
    .branch_inst_type_o(branch_inst_type_ex),
    .branch_req_o   (branch_req_ex),
    .push_ras_o     (push_ras_ex),
    .pop_ras_o      (pop_ras_ex),
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
`ifndef BRANCH_JUMP_DELAYED
    .is_fence_i         (is_fence_i_ex      ),
`endif
    .rd_csr_data      	(rd_csr_data        ),
    .illegal_inst_csr   (illegal_inst_csr   ),
    .access_wr        	(access_wr_ex       ),
    .access_illegal     (access_illegal     ),
    .alu_op1          	(alu_op1_forward    ),
    .alu_op2          	(alu_op2_forward    ),
    .jump_imm         	(jump_imm_ex        ),
    .inst_addr_plus_4   (inst_addr_plus_4_ex),
    .wr_mem_data_temp 	(wr_mem_data_temp   ),
    .mul_div_valid    	(mul_div_valid      ),
    .result_mul_div   	(result_mul_div     ),
`ifndef BRANCH_JUMP_DELAYED
    .branch_jump_en     (branch_jump_en_ex  ),
    .branch_jump_addr   (branch_jump_addr_ex),
`endif
    .exception_code  	(exception_code_ex  ),
    .exception_val   	(exception_val_ex   ),
    .mul_div_en       	(mul_div_en         ),
    .mul_div_func3    	(mul_div_func3      ),
    .access_addr        (access_addr_ex     ),
    .wr_mem_data      	(wr_mem_data_ex     ),
    .wr_mem_mask      	(wr_mem_mask_ex     ),
    .rd_mem_func3     	(rd_mem_func3_ex    ),
    .wr_reg_addr      	(wr_reg_addr_ex     ),
    .wr_reg_data      	(wr_reg_data_ex     ),
    .wr_csr_data      	(wr_csr_data        ),
    .wfi_req            (wfi_req            ),
    .mret_req           (mret_req           ),
    .branch_taken       (branch_taken_ex    ),
    .branch_target      (branch_target_ex   )
`ifndef BRANCH_JUMP_DELAYED,
    .branch_predict_success_o(branch_predict_success_ex)
`endif
);

mul_div #(
    .DATA_WIDTH     	(DATA_WIDTH),
    .REG_ADDR_WIDTH 	(REG_ADDR_WIDTH)
)u_mul_div(
    .clk         	(clk            ),
    .rst_n       	(rst_n          ),
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
    .rst_n          	(rst_n              ),
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
    .REG_ADDR_WIDTH (REG_ADDR_WIDTH)
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
`ifdef BRANCH_JUMP_DELAYED
    .inst_addr_plus_4_i   (inst_addr_plus_4_ex),
    .is_fence_i_i         (is_fence_i_ex),
    .predict_taken_i      (predict_taken_ex),
    .predict_target_i     (predict_target_ex),
    .branch_taken_i       (branch_taken_ex),
    .branch_target_i      (branch_target_ex),
    .branch_req_i         (branch_req_ex),
    .branch_inst_type_i   (branch_inst_type_ex),
    .push_ras_i           (push_ras_ex),
    .pop_ras_i            (pop_ras_ex),
    .is_fence_i_o         (is_fence_i_mem),
    .branch_taken_o       (branch_taken_mem),
    .branch_target_o      (branch_target_mem),
    .branch_req_o         (branch_req_mem),
    .branch_inst_type_o   (branch_inst_type_mem),
    .branch_predict_success_o(branch_predict_success_mem),
    .push_ras_o           (push_ras_mem),
    .pop_ras_o            (pop_ras_mem),
    .branch_jump_en_o     (branch_jump_en_mem),
    .branch_jump_addr_o   (branch_jump_addr_mem),
`endif
    .inst_addr_o    (inst_addr_mem),
    .inst_o         (inst_mem),
    .access_en_o    (access_en_mem),
    .access_wr_o    (access_wr_mem),
    .wr_reg_en_o    (wr_reg_en_mem),
    .wr_reg_addr_o  (wr_reg_addr_mem),
    .wr_reg_data_o  (wr_reg_data_mem)
);

Mem_Access #(
    .ADDR_WIDTH (ADDR_WIDTH),
    .DATA_WIDTH (DATA_WIDTH)
)u_Mem_Access(
    .clk                        (clk),
    .rst_n                      (rst_n),
    .access_addr                (access_addr_ex),
    .access_en                  (access_en_ex),
    .access_wr                  (access_wr_ex),
    .bus_tran_done              (bus_tran_done),
    .rd_dtcm_data               (rd_dtcm_data),
    .rd_bus_data                (bus_rdata),
    .rd_mem_func3               (rd_mem_func3_ex),
    .dtcm_sel                   (dtcm_sel),
    .bus_sel                    (bus_sel),
    .access_illegal             (access_illegal),
    .mem_access_ready           (mem_access_ready),
    .func3_expanded_data        (func3_expanded_data),
    .dtcm_rvalid                (dtcm_rvalid),
    .bus_rvalid                 (bus_rvalid)
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
    .access_addr(access_addr_ex),
    `ifdef BRANCH_JUMP_DELAYED
    .wr_en      (access_wr_ex && dtcm_sel && ~ex_mem_flush && ~ex_mem_stall),
    `else
    .wr_en      (access_wr_ex && dtcm_sel && ~ex_mem_stall),
    `endif
    .wr_data    (wr_mem_data_ex),
    .wr_mask    (wr_mem_mask_ex),
    .dtcm_download_en (dtcm_download_en   ),
    .dtcm_download_addr(dtcm_download_addr),
    .dtcm_download_data(dtcm_download_data),
    .rd_data    (rd_dtcm_data)
);

// MUX2: load data only for LOAD instructions, ALU result for everything else
// bus_rvalid 只对 load 指令选择 func3_expanded_data，非 load 指令（如 lui）固定传 ALU 结果
assign wr_reg_selected_data_mem = (dtcm_rvalid || bus_rvalid) ? func3_expanded_data : wr_reg_data_mem;

// MEM/WB wr_reg_en/wr_reg_addr bypass: bus loads skip EX/MEM, DTCM/ALU go through EX/MEM
assign wr_reg_selected_en_mem   = bus_rvalid ? wr_reg_en_ex   : wr_reg_en_mem;
assign wr_reg_selected_addr_mem = bus_rvalid ? wr_reg_addr_ex : wr_reg_addr_mem;

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
    .wr_reg_en_i    (wr_reg_selected_en_mem),
    .wr_reg_addr_i  (wr_reg_selected_addr_mem),
    .wr_reg_data_i  (wr_reg_selected_data_mem),
    .bus_rvalid_i   (bus_rvalid),
    .bus_rvalid_o   (bus_rvalid_r1),
    .inst_o         (inst_wb),
    .inst_addr_o    (inst_addr_wb),
    .wr_reg_en_o    (wr_reg_en_wb),
    .wr_reg_addr_o  (wr_reg_addr_wb),
    .wr_reg_data_o  (wr_reg_data_wb)
);

assign wr_reg_data = bus_rvalid ? wr_reg_data_mem : wr_reg_data_wb;
assign wr_reg_en   = bus_rvalid ? wr_reg_en_mem   : (wr_reg_en_wb && ~bus_rvalid_r2);
assign wr_reg_addr = bus_rvalid ? wr_reg_addr_mem : wr_reg_addr_wb;


// bus_rvalid 经 MEM_WB 延迟一拍后给 Data_Hazard_Forward 做 bus_done
always_ff @(posedge clk) begin
    bus_ready_r <= #1 mem_access_ready;
    bus_rvalid_r2 <= #1 bus_rvalid_r1;
end

assign bus_transfer   = (bus_ready_r && ~mem_access_ready) && ~ex_mem_flush;
assign bus_access_write  = access_wr_ex;
assign bus_access_wdata  = wr_mem_data_ex;
assign bus_access_addr  = access_addr_ex;
assign bus_access_wstrb  = wr_mem_mask_ex;


// ============================================================
// 诊断监控：追踪 PC 跳转和异常事件
// ============================================================
`ifdef DEBUG  // 仅在仿真时启用
logic [31:0] debug_cycle_cnt;
logic        debug_prev_ctrl_jump_en;
logic        debug_prev_trap_jump;

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        debug_cycle_cnt <= 0;
        debug_prev_ctrl_jump_en <= 0;
        debug_prev_trap_jump <= 0;
    end else begin
        debug_cycle_cnt <= debug_cycle_cnt + 1;
        debug_prev_ctrl_jump_en <= ctrl_jump_en;
        debug_prev_trap_jump <= trap_jump;
    end
end

// 捕捉 ctrl_jump_en 上升沿：打印跳转详情
always_ff @(posedge clk) begin
    if (ctrl_jump_en && ~debug_prev_ctrl_jump_en && rst_n) begin
        $display("[%0t] JUMP: PC=0x%08h → target=0x%08h | trap=%b branch=%b | pc_if=0x%08h pc_id=0x%08h pc_ex=0x%08h",
                 $time, inst_addr_if, ctrl_jump_addr, trap_jump, branch_jump_en_mem,
                 inst_addr_if, inst_addr_id, inst_addr_ex);
    end
end

// 捕捉 trap_jump 上升沿：打印异常/中断详情
always_ff @(posedge clk) begin
    if (trap_jump && ~debug_prev_trap_jump && rst_n) begin
        $display("[%0t] TRAP: trap_addr=0x%08h | exc_code=0x%04h exc_trap=%b | mepc=0x%08h",
                 $time, trap_jump_addr, exception_code, exception_trap,
                 inst_addr_id);
    end
end

// 当 PC 跳回 ITCM 低地址（疑似重启）时打印
logic [31:0] debug_last_itcm_pc;
always_ff @(posedge clk) begin
    if (!rst_n)
        debug_last_itcm_pc <= 0;
    else if (itcm_sel)
        debug_last_itcm_pc <= inst_addr_if;
end

// 检测 PC 突然跳回 ITCM 起始区域（0x00010000~0x000100FF）
// 排除正常的上电启动（前1000周期）
always_ff @(posedge clk) begin
    if (rst_n && debug_cycle_cnt > 1000 &&
        itcm_sel && inst_addr_if >= 32'h00010000 && inst_addr_if <= 32'h000100FF &&
        (debug_last_itcm_pc > 32'h00010100 || debug_last_itcm_pc == 0)) begin
        $display("[%0t] *** RESTART DETECTED: pc=0x%08h last_itcm_pc=0x%08h cycle=%0d",
                 $time, inst_addr_if, debug_last_itcm_pc, debug_cycle_cnt);
    end
end

// 每隔 ~50ms 打印一次周期计数和当前 PC（可选，观察长时间运行状态）
logic [31:0] debug_heartbeat_cnt;
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        debug_heartbeat_cnt <= 0;
    else
        debug_heartbeat_cnt <= debug_heartbeat_cnt + 1;
end
always_ff @(posedge clk) begin
    if (rst_n && (debug_heartbeat_cnt % 5000000 == 0) && debug_heartbeat_cnt > 0) begin
        $display("[%0t] HB: pc=0x%08h cycle=%0d trap_jump=%b exc_code=0x%04h",
                 $time, inst_addr_if, debug_cycle_cnt, trap_jump, exception_code);
    end
end
`endif

endmodule
