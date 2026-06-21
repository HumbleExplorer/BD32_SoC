`include "./../SoC_Config.sv"
`include "./../RV32_inst_Define.sv"
timeunit 1ns;
timeprecision 1ps;
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
(* MAX_FANOUT = 16 *) logic                       trap_jump;
logic   [ADDR_WIDTH-1:0]    trap_jump_addr;
logic   [1:0]               priv_mode;
logic                       waiting_int;
(* MAX_FANOUT = 16 *) logic                       load_use_flag;
logic                       bus_access_ready;
logic                       mul_ready;
logic                       div_ready;
logic                       mul_div_ready;     // = mul_ready & div_ready（给 CSR 用）
logic                       mul_valid_wbck;
logic                       div_valid_wbck;
logic   [DATA_WIDTH-1:0]    mul_result_wbck;
logic   [DATA_WIDTH-1:0]    div_result_wbck;
assign  mul_div_ready = mul_ready & div_ready;

// OITF 信号
logic                               oitf_stall;
logic                               oitf_retire_valid;
logic   [REG_ADDR_WIDTH-1:0]        oitf_retire_rd_addr;
logic   [DATA_WIDTH-1:0]            oitf_retire_rd_data;
logic                               oitf_retire_rd_wen;
logic                               lp_valid;
logic                               lp_is_div;

logic   [DATA_WIDTH-2:0]    exception_code_if;
logic   [DATA_WIDTH-2:0]    exception_code_id;
logic   [DATA_WIDTH-2:0]    exception_code_ex;
logic   [DATA_WIDTH-1:0]    exception_val_if;
logic   [DATA_WIDTH-1:0]    exception_val_id;
logic   [DATA_WIDTH-1:0]    exception_val_ex;

(* MAX_FANOUT = 16 *) logic                       pc_stall;
logic                       ctrl_jump_en;
logic   [ADDR_WIDTH-1:0]    ctrl_jump_addr;
logic                       if_id_stall;
logic                       if_id_flush;
logic                       id_ex_stall;
logic                       id_ex_flush;
logic                       ex_mem_stall;
(* MAX_FANOUT = 16 *) logic                       ex_mem_flush;
logic                       mem_wb_stall;
logic                       mem_wb_flush;
logic   [ADDR_WIDTH-1:0]    exception_inst_addr;
(* MAX_FANOUT = 16 *) logic                       exception_trap;
logic   [DATA_WIDTH-2:0]    exception_code;
logic   [DATA_WIDTH-1:0]    exception_val;
logic   [ADDR_WIDTH-1:0]    next_inst_addr;

// Data_Hazard
logic   [DATA_WIDTH-1:0]    alu_op1_from_id_ex;
logic   [DATA_WIDTH-1:0]    alu_op2_from_id_ex;
logic   [DATA_WIDTH-1:0]    alu_op1_forward;
logic   [DATA_WIDTH-1:0]    alu_op2_forward;
logic   [DATA_WIDTH-1:0]    access_wdata_temp;
logic   [DATA_WIDTH-1:0]    reg_rs2_rdata_ex;

//RegFile
logic                       reg_rd_wen;
logic   [REG_ADDR_WIDTH-1:0]reg_rs1_raddr;
logic   [REG_ADDR_WIDTH-1:0]reg_rs2_raddr;
logic   [DATA_WIDTH-1:0]    reg_rs1_rdata;
logic   [DATA_WIDTH-1:0]    reg_rs2_rdata;
logic   [REG_ADDR_WIDTH-1:0]reg_rd_waddr;
logic   [DATA_WIDTH-1:0]    reg_rd_wdata;

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
logic                       csr_en_id;
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
logic   [2:0]               access_func3_ex;
logic   [DATA_WIDTH-1:0]    access_wdata_ex;
logic   [ALIGN_BYTES-1:0]   access_wmask_ex;
logic                       reg_rd_wen_ex;
logic   [REG_ADDR_WIDTH-1:0]reg_rd_waddr_ex;
logic   [DATA_WIDTH-1:0]    reg_rd_wdata_ex;

logic   [REG_ADDR_WIDTH-1:0]reg_rs1_raddr_ex;
logic   [REG_ADDR_WIDTH-1:0]reg_rs2_raddr_ex;
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


//CSR
logic                       csr_en;
logic   [CSR_ADDR_WIDTH-1:0]csr_addr;
logic   [DATA_WIDTH-1:0]    csr_rdata;
logic   [DATA_WIDTH-1:0]    csr_wdata;
logic                       illegal_inst_csr;

// MEM
logic   [ADDR_WIDTH-1:0]    inst_addr_mem;
logic   [DATA_WIDTH-1:0]    inst_mem;
logic                       reg_rd_wen_mem;
logic   [REG_ADDR_WIDTH-1:0]reg_rd_waddr_mem;
logic   [DATA_WIDTH-1:0]    reg_rd_wdata_mem;
logic   [DATA_WIDTH-1:0]    func3_expanded_data;
logic   [DATA_WIDTH-1:0]    reg_rd_wdata_selected_mem;   // MUX2 output: load data or ALU result
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
logic   [DATA_WIDTH-1:0]    dtcm_rdata;
logic                       dtcm_sel;
logic                       bus_sel;
logic                       dtcm_rvalid;
logic                       bus_rvalid;
logic                       bus_rvalid_r1;
logic                       bus_ready_r;
// MEM/WB bypass for bus loads (reg_rd_wen/addr from EX stage, bypassing EX/MEM)
logic                       reg_rd_wen_selected_mem;
logic   [REG_ADDR_WIDTH-1:0]reg_rd_waddr_selected_mem;


// WB
logic   [ADDR_WIDTH-1:0]    inst_addr_wb;
logic   [DATA_WIDTH-1:0]    inst_wb;
logic                       reg_rd_wen_wb;
logic   [REG_ADDR_WIDTH-1:0]reg_rd_waddr_wb;
logic   [DATA_WIDTH-1:0]    reg_rd_wdata_wb;


`ifdef ENABLE_HPM
// HPM：流水线 valid 链
logic                       if_id_valid;
logic                       id_ex_valid;
logic                       ex_mem_valid;
logic                       mem_wb_valid;
logic                       hpm_valid;
// HPM：指令类型（Decoder → ID_EX → EX_MEM → MEM_WB → CSR）
logic   [2:0]               inst_type_id;
logic   [2:0]               inst_type_ex;
logic   [2:0]               inst_type_mem;
logic   [2:0]               inst_type_wb;
logic   [2:0]               hpm_inst_type;
logic                       hpm_mispredict;
`ifdef BRANCH_JUMP_DELAYED
assign hpm_mispredict = ~branch_predict_success_mem;
`else
assign hpm_mispredict = ~branch_predict_success_ex;
`endif
assign hpm_valid = mem_wb_valid & ~mem_wb_stall;
assign hpm_inst_type = inst_type_wb;
`endif

Pipeline_Ctrl #(
    .ADDR_WIDTH(ADDR_WIDTH),
    .DATA_WIDTH(DATA_WIDTH)
)u_Pipeline_Ctrl(
    .clk            (clk),
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
    .waiting_int           	(waiting_int          ),
    .load_use_flag       	(load_use_flag        ),
    .branch_taken           (branch_taken_ex      ),
    .branch_target          (branch_target_ex     ),
    .bus_access_ready    	(bus_access_ready     ),
    .oitf_stall          	(oitf_stall           ),
    .reg_rd_wen_wb           (reg_rd_wen_wb         ),
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
    .reg_rs1_raddr_id     	(reg_rs1_raddr      ),
    .reg_rs2_raddr_id     	(reg_rs2_raddr      ),
    .reg_rd_wen_ex       	(reg_rd_wen_ex      ),
    .reg_rs1_raddr_ex     	(reg_rs1_raddr_ex   ),
    .reg_rs2_raddr_ex     	(reg_rs2_raddr_ex   ),
    .reg_rd_waddr_ex     	(reg_rd_waddr_ex    ),
    .access_en_ex       	(access_en_ex       ),
    .access_wr_ex       	(access_wr_ex       ),
    .access_en_mem      	(access_en_mem      ),
    .access_wr_mem      	(access_wr_mem      ),
    .reg_rd_wen_mem      	(reg_rd_wen_mem     ),
    .reg_rd_waddr_mem    	(reg_rd_waddr_mem   ),
    .reg_rd_wen_wb       	(reg_rd_wen      ),
    .reg_rd_waddr_wb     	(reg_rd_waddr    ),
    .lp_retire_valid        (oitf_retire_valid  ),
    .lp_retire_waddr        (oitf_retire_rd_addr),
    .lp_retire_wdata        (oitf_retire_rd_data),
    .alu_op1_from_id_ex 	(alu_op1_from_id_ex ),
    .alu_op2_from_id_ex 	(alu_op2_from_id_ex ),
    .reg_rs2_rdata_ex    	(reg_rs2_rdata_ex   ),
    .reg_rd_wdata_mem    	(reg_rd_wdata_mem   ),
    .reg_rd_wdata_wb     	(reg_rd_wdata_wb    ),
    .bus_sel                (bus_sel            ),
    .bus_rvalid_r1          (bus_rvalid_r1      ),
    .bus_access_ready       (bus_access_ready   ),
    .load_use_flag      	(load_use_flag      ),
    .alu_op1_o          	(alu_op1_forward    ),
    .alu_op2_o          	(alu_op2_forward    ),
    .access_wdata_temp   	(access_wdata_temp  )
);

Dynamic_Branch_Predictor #(
    .ADDR_WIDTH     (ADDR_WIDTH ),
    .DATA_WIDTH     (DATA_WIDTH ),
    .ALIGN_WIDTH    (ALIGN_WIDTH)
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
`ifdef ENABLE_HPM
    ,
    .valid_o            (if_id_valid)
`endif
);

Decoder #(
    .ADDR_WIDTH     (ADDR_WIDTH),
    .DATA_WIDTH     (DATA_WIDTH),
    .REG_ADDR_WIDTH (REG_ADDR_WIDTH),
    .CSR_ADDR_WIDTH (CSR_ADDR_WIDTH)
)u_Decoder(
    .inst_addr      (inst_addr_id),
    .inst           (inst_id),
    .reg_rs1_raddr  (reg_rs1_raddr),
    .reg_rs2_raddr  (reg_rs2_raddr),
    .priv_mode      (priv_mode),
    .reg_rs1_rdata  (reg_rs1_rdata),
    .reg_rs2_rdata  (reg_rs2_rdata),
    .alu_op1        (alu_op1_id),
    .alu_op2        (alu_op2_id),
    .imm            (imm_id),
    .access_wr      (access_wr_id),
    .access_en      (access_en_id),
    .csr_en         (csr_en_id),
    .csr_addr       (csr_addr_id),
    .is_fence_i     (is_fence_i_id),
    .branch_inst_type(branch_inst_type_id),
    .branch_req     (branch_req_id),
    .push_ras       (push_ras_id),
    .pop_ras        (pop_ras_id),
    .exception_code (exception_code_id),
    .exception_val  (exception_val_id)
`ifdef ENABLE_HPM
    ,
    .inst_type      (inst_type_id)
`endif
);

// OITF：ID 阶段识别 mul/div 指令，istruction type 由 Decoder inst_type 给出
// oitf_stall 计算全部在 OITF 模块内部

RegFile #(
    .DATA_WIDTH     (DATA_WIDTH),
    .REG_ADDR_WIDTH (REG_ADDR_WIDTH),
    .REGFILE_NUM    (REGFILE_NUM)
)u_RegFile(
    .clk            (clk),
    .rst_n          (rst_n),
    //读端口
    .reg_rs1_raddr  (reg_rs1_raddr),
    .reg_rs2_raddr  (reg_rs2_raddr),
    .reg_rs1_rdata  (reg_rs1_rdata),
    .reg_rs2_rdata  (reg_rs2_rdata),
    //写端口1：正常 WB 路径
    .reg_rd_wen     (reg_rd_wen),
    .reg_rd_waddr   (reg_rd_waddr),
    .reg_rd_wdata   (reg_rd_wdata),
    //写端口2：OITF 退休路径
    .reg_rd_wen2    (oitf_retire_valid && oitf_retire_rd_wen),
    .reg_rd_waddr2  (oitf_retire_rd_addr),
    .reg_rd_wdata2  (oitf_retire_rd_data)
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
    .reg_rs2_rdata_i(reg_rs2_rdata),
    .jump_imm_i     (jump_imm_id),
    .inst_addr_plus_4_i(inst_addr_plus_4_id),
    .reg_rs1_raddr_i(reg_rs1_raddr),
    .reg_rs2_raddr_i(reg_rs2_raddr),
    .access_wr_i    (access_wr_id),
    .access_en_i    (access_en_id),
    .csr_en_i       (csr_en_id),
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
    .reg_rs2_rdata_o(reg_rs2_rdata_ex),
    .access_wr_o    (access_wr_ex),
    .access_en_o    (access_en_ex),
    .csr_en_o       (csr_en),
    .csr_addr_o     (csr_addr),
    .is_fence_i_o   (is_fence_i_ex),
    .branch_inst_type_o(branch_inst_type_ex),
    .branch_req_o   (branch_req_ex),
    .push_ras_o     (push_ras_ex),
    .pop_ras_o      (pop_ras_ex),
    .reg_rs1_raddr_o(reg_rs1_raddr_ex),
    .reg_rs2_raddr_o(reg_rs2_raddr_ex)
`ifdef ENABLE_HPM
    ,
    .inst_type_i    (inst_type_id),
    .inst_type_o    (inst_type_ex),
    .valid_i        (if_id_valid),
    .valid_o        (id_ex_valid)
`endif
);

Executer #(
    .ADDR_WIDTH     	(ADDR_WIDTH    ),
    .DATA_WIDTH     	(DATA_WIDTH    ),
    .REG_ADDR_WIDTH 	(REG_ADDR_WIDTH),
    .CSR_ADDR_WIDTH 	(CSR_ADDR_WIDTH),
    .ALIGN_BYTES    	(ALIGN_BYTES   ),
    .ALIGN_WIDTH    	(ALIGN_WIDTH   )
)u_Executer(
    .clk                (clk                ),
    .rst_n              (rst_n              ),
    .inst_addr        	(inst_addr_ex       ),
    .inst             	(inst_ex            ),
    .imm              	(imm_ex             ),
    .predict_taken    	(predict_taken_ex   ),
    .predict_target	    (predict_target_ex  ),
`ifndef BRANCH_JUMP_DELAYED
    .is_fence_i         (is_fence_i_ex      ),
`endif
    .csr_rdata        	(csr_rdata          ),
    .illegal_inst_csr   (illegal_inst_csr   ),
    .access_en          (access_en_ex       ),
    .access_wr         	(access_wr_ex       ),
    .alu_op1          	(alu_op1_forward    ),
    .alu_op2          	(alu_op2_forward    ),
    .reg_rs1_raddr      (reg_rs1_raddr_ex   ),
    .reg_rs2_raddr      (reg_rs2_raddr_ex   ),
    .jump_imm         	(jump_imm_ex        ),
    .inst_addr_plus_4   (inst_addr_plus_4_ex),
    .access_wdata_temp 	(access_wdata_temp  ),
`ifndef BRANCH_JUMP_DELAYED
    .branch_jump_en     (branch_jump_en_ex  ),
    .branch_jump_addr   (branch_jump_addr_ex),
`endif
    .exception_code  	(exception_code_ex  ),
    .exception_val   	(exception_val_ex   ),
    .lp_valid           (lp_valid           ),
    .lp_is_div          (lp_is_div          ),
    .mul_ready          (mul_ready          ),
    .div_ready          (div_ready          ),
    .mul_valid_wbck     (mul_valid_wbck     ),
    .div_valid_wbck     (div_valid_wbck     ),
    .mul_result_wbck    (mul_result_wbck    ),
    .div_result_wbck    (div_result_wbck    ),
    .access_addr        (access_addr_ex     ),
    .access_wdata      	(access_wdata_ex    ),
    .access_wmask      	(access_wmask_ex    ),
    .access_func3     	(access_func3_ex    ),
    .reg_rd_wen       	(reg_rd_wen_ex      ),
    .reg_rd_waddr     	(reg_rd_waddr_ex    ),
    .reg_rd_wdata      	(reg_rd_wdata_ex    ),
    .csr_wdata        	(csr_wdata          ),
    .wfi_req            (wfi_req            ),
    .mret_req           (mret_req           ),
    .branch_taken       (branch_taken_ex    ),
    .branch_target      (branch_target_ex   )
`ifndef BRANCH_JUMP_DELAYED,
    .branch_predict_success_o(branch_predict_success_ex)
`endif
);

CSR_Reg_Access #(
    .ADDR_WIDTH     (ADDR_WIDTH),
    .DATA_WIDTH     (DATA_WIDTH),
    .CSR_ADDR_WIDTH (CSR_ADDR_WIDTH)
)u_CSR_Reg_Access(
    .clk            	(clk                ),
    .rst_n          	(rst_n              ),
    .csr_en              (csr_en             ),
    .csr_addr       	(csr_addr           ),
    .csr_wdata    	    (csr_wdata          ),
    .csr_rdata    	    (csr_rdata          ),
    .exception_inst_addr(exception_inst_addr),
    .next_inst_addr 	(next_inst_addr     ),
    .bus_access_ready   (bus_access_ready   ),
    .mul_div_ready      (mul_div_ready      ),
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
    .trap_jump_addr 	(trap_jump_addr     ),
    .waiting_int        (waiting_int        )
`ifdef ENABLE_HPM
    ,
    .hpm_valid          (hpm_valid          ),
    .hpm_inst_type      (hpm_inst_type      ),
    .hpm_mispredict     (hpm_mispredict)
`endif
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
    .reg_rd_wen_i   (reg_rd_wen_ex),
    .reg_rd_waddr_i (reg_rd_waddr_ex),
    .reg_rd_wdata_i (reg_rd_wdata_ex),
    .lp_valid_i     (lp_valid),
    .access_en_i    (access_en_ex),
    .access_wr_i    (access_wr_ex),
    .bus_sel        (bus_sel),
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
    .reg_rd_wen_o   (reg_rd_wen_mem),
    .reg_rd_waddr_o (reg_rd_waddr_mem),
    .reg_rd_wdata_o (reg_rd_wdata_mem)
`ifdef ENABLE_HPM
    ,
    .inst_type_i    (inst_type_ex),
    .inst_type_o    (inst_type_mem),
    .valid_i        (id_ex_valid),
    .valid_o        (ex_mem_valid)
`endif
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
    .dtcm_rdata                 (dtcm_rdata),
    .rd_bus_data                (bus_rdata),
    .access_func3               (access_func3_ex),
    .dtcm_sel                   (dtcm_sel),
    .bus_sel                    (bus_sel),
    .bus_access_ready           (bus_access_ready),
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
    .wr_data    (access_wdata_ex),
    .wr_mask    (access_wmask_ex),
    .dtcm_download_en (dtcm_download_en   ),
    .dtcm_download_addr(dtcm_download_addr),
    .dtcm_download_data(dtcm_download_data),
    .rd_data    (dtcm_rdata)
);

// MUX2: load data only for LOAD instructions, ALU result for everything else
// bus_rvalid 只对 load 指令选择 func3_expanded_data，非 load 指令（如 lui）固定传 ALU 结果
assign reg_rd_wdata_selected_mem = (dtcm_rvalid || bus_rvalid) ? func3_expanded_data : reg_rd_wdata_mem;

// MEM/WB reg_rd_wen/reg_rd_waddr bypass: bus loads skip EX/MEM, DTCM/ALU go through EX/MEM
assign reg_rd_wen_selected_mem   = bus_rvalid ? reg_rd_wen_ex   : reg_rd_wen_mem;
assign reg_rd_waddr_selected_mem = bus_rvalid ? reg_rd_waddr_ex : reg_rd_waddr_mem;

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
    .reg_rd_wen_i   (reg_rd_wen_selected_mem),
    .reg_rd_waddr_i (reg_rd_waddr_selected_mem),
    .reg_rd_wdata_i (reg_rd_wdata_selected_mem),
    .inst_o         (inst_wb),
    .inst_addr_o    (inst_addr_wb),
    .reg_rd_wen_o   (reg_rd_wen_wb),
    .reg_rd_waddr_o (reg_rd_waddr_wb),
    .reg_rd_wdata_o (reg_rd_wdata_wb)
`ifdef ENABLE_HPM
    ,
    .inst_type_i    (inst_type_mem),
    .inst_type_o    (inst_type_wb),
    .valid_i        (ex_mem_valid),
    .valid_o        (mem_wb_valid)
`endif
);

// ==========================================================================
// OITF（非阻塞乘除法）
// ==========================================================================
OITF #(
    .OITF_DEPTH     (4),
    .DATA_WIDTH     (DATA_WIDTH),
    .REG_ADDR_WIDTH (REG_ADDR_WIDTH),
    .NUM_LP_UNITS   (2)
) u_OITF (
    .clk            (clk),
    .rst_n          (rst_n),
    // EX 阶段长周期指令派发
    .lp_valid       (lp_valid),
    .lp_unit_id     (lp_is_div),
    .disp_rd_addr   (reg_rd_waddr_ex),
    .disp_rd_wen    (lp_valid),
    // RAW 检查（EX 阶段）
    .reg_rs1_raddr_ex(reg_rs1_raddr_ex),
    .ex_rs1_valid   (|reg_rs1_raddr_ex),
    .reg_rs2_raddr_ex(reg_rs2_raddr_ex),
    .ex_rs2_valid   (|reg_rs2_raddr_ex),
    // WAW 检查（EX 阶段）
    .reg_rd_waddr_ex(reg_rd_waddr_ex),
    .reg_rd_wen_ex  (reg_rd_wen_ex),
    // 通用长周期单元状态数组
    .unit_ready     ({div_ready      ,mul_ready         }),
    .unit_wbck_valid({div_valid_wbck ,mul_valid_wbck    }),
    .result_wbck    ({div_result_wbck,mul_result_wbck   }),
    // 输出
    .oitf_stall     (oitf_stall),
    .retire_valid   (oitf_retire_valid),
    .retire_rd_addr (oitf_retire_rd_addr),
    .retire_rd_data (oitf_retire_rd_data),
    .retire_rd_wen  (oitf_retire_rd_wen),
    .flush          (ex_mem_flush)
);

// Port1 写端口：正常 WB 路径（bus_rvalid 直通否则走 MEM_WB）
assign reg_rd_wdata = bus_rvalid ? reg_rd_wdata_mem : reg_rd_wdata_wb;
assign reg_rd_wen   = bus_rvalid ? reg_rd_wen_mem   : reg_rd_wen_wb;
assign reg_rd_waddr = bus_rvalid ? reg_rd_waddr_mem : reg_rd_waddr_wb;


// bus_rvalid 经 MEM_WB 延迟一拍后给 Data_Hazard_Forward 做 bus_done
always_ff @(posedge clk) begin
    bus_ready_r <= #1 bus_access_ready;
    bus_rvalid_r1 <= #1 bus_rvalid;
end

assign bus_transfer   = (bus_ready_r && ~bus_access_ready) && ~ex_mem_flush && ~(waiting_int || oitf_stall);
assign bus_access_write  = access_wr_ex;
assign bus_access_wdata  = access_wdata_ex;
assign bus_access_addr  = access_addr_ex;
assign bus_access_wstrb  = access_wmask_ex;



endmodule
