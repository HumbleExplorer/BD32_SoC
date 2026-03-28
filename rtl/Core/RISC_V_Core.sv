`include "./../SoC_Config.sv"
`include "./../RV32_inst_Define.sv"
module RISC_V_Core #(
    parameter ITCM_FILE = `ITCM_FILE,
    parameter DTCM_FILE = `DTCM_FILE,
    parameter ADDR_WIDTH = `ADDR_WIDTH,
    parameter DATA_WIDTH = `DATA_WIDTH,
    parameter REGFILE_NUM = `REGFILE_NUM,
    parameter REG_ADDR_WIDTH = `REG_ADDR_WIDTH,
    parameter CSR_ADDR_WIDTH = `CSR_ADDR_WIDTH,
    parameter ALIGN_BYTES = `ALIGN_BYTES,
    parameter ALIGN_WIDTH = `ALIGN_WIDTH
)(
    input   logic                       clk,
    input   logic                       rst_n,
    // from update
    input   logic                       itcm_wr_en,
    input   logic   [ADDR_WIDTH-1:0]    itcm_wr_addr,
    input   logic   [DATA_WIDTH-1:0]    itcm_wr_data,
    // from clint
    input   logic   [DATA_WIDTH-1:0]    clint_rdata,
    input   logic   [2*DATA_WIDTH-1:0]  mtime_shadow,
    input   logic                       software_int,
    input   logic                       timer_int,
    // to clint
    output  logic                       clint_sel,
    // from plic
    input   logic                       external_int,
    // to plic
    output  logic                       plic_sel,
    // from bus
    input   logic   [DATA_WIDTH-1:0]    bus_rdata,
    input   logic                       bus_tran_done,
    // to bus
    output  logic                       bus_sel,
    // to clint/plic/bus
    output  logic   [ADDR_WIDTH-1:0]    access_addr,
    output  logic                       access_wr,
    output  logic   [DATA_WIDTH-1:0]    access_wr_data,
    output  logic   [ALIGN_BYTES-1:0]   access_wr_mask
);

// Pipeline Ctrl
logic                       branch_jump_en;
logic   [ADDR_WIDTH-1:0]    branch_jump_addr;
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
logic   [1:0]   forward_A;
logic   [1:0]   forward_B;
logic           forward_C;
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
logic   [ADDR_WIDTH-1:0]    pc;
logic   [DATA_WIDTH-1:0]    inst;
logic                       predict_taken_if;
logic   [ADDR_WIDTH-1:0]    predict_target_pc_if;


// ID
logic   [ADDR_WIDTH-1:0]    inst_addr_id;
logic   [DATA_WIDTH-1:0]    inst_id;
logic                       predict_taken_id;
logic   [ADDR_WIDTH-1:0]    predict_target_pc_id;
logic   [DATA_WIDTH-1:0]    alu_op1_id;
logic   [DATA_WIDTH-1:0]    alu_op2_id;
logic   [DATA_WIDTH-1:0]    imm_id;
logic                       access_en_id;
logic                       access_wr_id;
logic                       wr_reg_en_id;
logic                       access_csr_en_id;
logic   [CSR_ADDR_WIDTH-1:0]csr_addr_id;

// EX
logic   [ADDR_WIDTH-1:0]    inst_addr_ex;
logic   [DATA_WIDTH-1:0]    inst_ex;
logic                       predict_taken_ex;
logic   [ADDR_WIDTH-1:0]    predict_target_pc_ex;
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
// logic   [ADDR_WIDTH-1:0]    access_addr;


logic   [DATA_WIDTH-1:0]    rd_dtcm_data;
logic   [DATA_WIDTH-1:0]    rd_clint_data;
logic   [DATA_WIDTH-1:0]    rd_plic_data;
logic   [2:0]               rd_mem_func3;
logic   [DATA_WIDTH-1:0]    wr_mem_data;
logic   [ALIGN_BYTES-1:0]   wr_mem_mask;
logic                       dtcm_sel;


// WB
logic   [ADDR_WIDTH-1:0]    inst_addr_wb;
logic   [DATA_WIDTH-1:0]    inst_wb;

Pipeline_Ctrl #(
    .ADDR_WIDTH(ADDR_WIDTH),
    .DATA_WIDTH(DATA_WIDTH)
)u_Pipeline_Ctrl(
    .branch_jump_en      	(branch_jump_en       ),
    .branch_jump_addr    	(branch_jump_addr     ),
    .trap_jump           	(trap_jump            ),
    .trap_jump_addr      	(trap_jump_addr       ),
    .priv_mode           	(priv_mode            ),
    .load_use_flag       	(load_use_flag        ),
    .mem_access_ready    	(mem_access_ready     ),
    .mul_div_ready       	(mul_div_ready        ),
    .inst_addr_if        	(pc                   ),
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
    .bus_sel                (bus_sel),
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
    .mem_addr_ex            (mem_addr_ex        ),
    .forward_A          	(forward_A          ),
    .forward_B          	(forward_B          ),
    .forward_C          	(forward_C          ),
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
    .pc              (pc             ),
    .branch_pc       (inst_addr_ex   ),
    .branch_taken    (branch_taken   ),
    .branch_target   (branch_target  ),  
    .branch_req      (branch_req     ),
    .branch_predict_success(branch_predict_success),
    .branch_inst_type(branch_inst_type),
    .push_ras        (push_ras       ),
    .pop_ras         (pop_ras        )
);

PC_counter #(
    .ADDR_WIDTH(ADDR_WIDTH)
)u_PC_counter(
    .clk            (clk),
    .rst_n          (rst_n),
    .jump_en        (ctrl_jump_en),
    .jump_addr      (ctrl_jump_addr),
    .stall          (pc_stall),
    .pc             (pc),
    .exception_code (exception_code_if),
    .exception_val  (exception_val_if)
    // .inst_addr_o    (inst_addr_if)
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
    .inst_addr      (pc),
    .inst_o         (inst)
);  

IF_ID #(
    .ADDR_WIDTH         (ADDR_WIDTH),
    .DATA_WIDTH         (DATA_WIDTH)
)u_IF_ID(
    .clk                (clk),
    .rst_n              (rst_n),
    .stall              (if_id_stall),
    .flush              (if_id_flush),
    .inst_addr_i        (pc),
    // .inst_i         (inst),
    .inst_i             (inst),
    .predict_taken_i    (predict_taken_if),
    .predict_target_pc_i(predict_target_pc_if),
    .inst_addr_o        (inst_addr_id),
    .inst_o             (inst_id),
    .predict_taken_o    (predict_taken_id),
    .predict_target_pc_o(predict_target_pc_id)
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
    .predict_target_pc_i(predict_target_pc_id),
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
    .predict_target_pc_o(predict_target_pc_ex),
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
    .predict_target_pc	(predict_target_pc_ex),
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
    .inst_addr_o    (inst_addr_mem),
    .inst_o         (inst_mem),
    .access_en_o    (access_en),
    .access_wr_o    (access_wr),
    .mem_addr_o     (access_addr),
    .rd_mem_func3_o (rd_mem_func3),
    .wr_mem_data_o  (wr_mem_data),
    .wr_mem_mask_o  (wr_mem_mask),
    .wr_reg_en_o    (wr_reg_en_mem),
    .wr_reg_addr_o  (wr_reg_addr_mem),
    .wr_reg_data_o  (wr_reg_data_from_ex_mem)
);

Mem_Access #(
    .ADDR_WIDTH (ADDR_WIDTH),
    .DATA_WIDTH (DATA_WIDTH)
)u_Mem_Access(
    .access_addr                (access_addr),
    .access_en                  (access_en),
    .access_wr                  (access_wr),
    .bus_tran_done              (bus_tran_done),
    .rd_dtcm_data               (rd_dtcm_data),
    .rd_clint_data              (rd_clint_data),
    .rd_plic_data               (rd_plic_data),
    .rd_bus_data                (bus_rdata),
    .rd_mem_func3               (rd_mem_func3),
    .wr_reg_data_from_ex_mem    (wr_reg_data_from_ex_mem),
    .dtcm_sel                   (dtcm_sel),
    .clint_sel                  (clint_sel),
    .plic_sel                   (plic_sel),
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

// assign access_addr = access_addr;
// assign access_wr = access_wr;
assign access_wr_data = wr_mem_data;
assign access_wr_mask = wr_mem_mask;

endmodule
