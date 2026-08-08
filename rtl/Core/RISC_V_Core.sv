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
    input   logic                       bus_tran_done,
    input   logic                       bus_ready,
    input   logic   [DATA_WIDTH-1:0]    bus_rdata,
    input   logic   [1:0]               bus_resp,
    // to bus
    output  logic                       bus_transfer,
    output  logic                       bus_access_write,
    output  logic   [ADDR_WIDTH-1:0]    bus_access_addr,
    output  logic   [ALIGN_BYTES-1:0]   bus_access_wstrb,
    output  logic   [DATA_WIDTH-1:0]    bus_access_wdata,
    // Debug Module 接口
    input   logic                       dbg_halt_req,
    output  logic                       dbg_halted,
    input   logic                       dbg_resume_req,
    input   logic                       dbg_step,
    input   logic                       dbg_ebreakm,
    output  logic                       ebreak_halt,      // ebreak 进入 debug 模式请求（ID 级）
    input   logic                       dbg_reg_we,
    input   logic   [REG_ADDR_WIDTH-1:0] dbg_reg_addr,
    input   logic   [DATA_WIDTH-1:0]    dbg_reg_wdata,
    output  logic   [DATA_WIDTH-1:0]    dbg_reg_rdata,
    output  logic   [DATA_WIDTH-1:0]    dbg_dpc,
    input   logic   [DATA_WIDTH-1:0]    dbg_pc_wdata,
    // Trigger：硬件断点 + 数据观察点，多路打包
    input   logic   [`TRIGGER_NUM-1:0]  trigger_en,
    input   logic   [`TRIGGER_NUM-1:0]  trigger_exec_en,
    input   logic   [`TRIGGER_NUM-1:0]  trigger_load_en,
    input   logic   [`TRIGGER_NUM-1:0]  trigger_store_en,
    input   logic   [`TRIGGER_NUM*2-1:0] trigger_size,
    input   logic   [`TRIGGER_NUM*DATA_WIDTH-1:0] trigger_addr,
    output  logic                       trigger_hit,
    // Debug CSR 访问（Abstract 通用 CSR 读写）
    input   logic                       dbg_csr_we,
    input   logic   [CSR_ADDR_WIDTH-1:0] dbg_csr_addr,
    input   logic   [DATA_WIDTH-1:0]    dbg_csr_wdata,
    output  logic   [DATA_WIDTH-1:0]    dbg_csr_rdata,
    // System Bus Access (SBA) — 调试器读写 TCM
    input   logic                       sba_req_valid,
    input   logic   [ADDR_WIDTH-1:0]    sba_addr,
    input   logic   [DATA_WIDTH-1:0]    sba_wdata,
    input   logic                       sba_write,
    input   logic   [2:0]               sba_size,
    input   logic   [ALIGN_BYTES-1:0]   sba_be,           // SBA 字节使能（子字写）
    output  logic                       sba_rsp_valid,
    output  logic   [DATA_WIDTH-1:0]    sba_rdata,
    output  logic                       sba_error
);

// Pipeline Ctrl
logic                       branch_jump_en_ex;
logic   [ADDR_WIDTH-1:0]    branch_jump_addr_ex;
(* MAX_FANOUT = 16 *) logic                       trap_jump;
logic   [ADDR_WIDTH-1:0]    trap_jump_addr;
logic                       trap_jump_exc;
logic   [1:0]               priv_mode;
logic                       waiting_int;
(* MAX_FANOUT = 16 *) logic                       load_use_flag;
logic                       mul_ready;
logic                       div_ready;
logic                       mul_valid_wbck;
logic                       div_valid_wbck;
logic   [DATA_WIDTH-1:0]    mul_result_wbck;
logic   [DATA_WIDTH-1:0]    div_result_wbck;

// OITF 信号
logic                               oitf_stall;
logic                               oitf_retire_valid;
logic   [REG_ADDR_WIDTH-1:0]        oitf_retire_rd_addr;
logic   [DATA_WIDTH-1:0]            oitf_retire_rd_data;
logic                               oitf_retire_rd_wen;
logic                               lp_valid;
logic                               lp_is_div;

// 子模块异常条件线（1-bit，编码在本模块统一完成）
logic                       if_addr_misalign;
logic                       if_access_fault;
logic                       id_illegal_inst;
logic                       id_ecall;
logic                       id_ebreak;
logic                       ex_access_illegal;
logic                       ex_addr_misalign;
logic                       ex_illegal_csr;

// 编码后的异常码/值（送 Pipeline_Ctrl 仲裁）
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
logic                       oitf_flush;
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
logic                       fwd_a_hit;
logic                       fwd_b_hit;

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
logic                       is_nop_id;
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
// =========================================================================
// Trigger 比较：IF 级 execute 地址匹配（硬件断点）+
//             EX 级 load/store 有效地址匹配（数据观察点），按读写类型与访问宽度过滤
// =========================================================================
logic [`TRIGGER_NUM-1:0] trigger_hit_vec;   // IF 级（指令地址）
logic [`TRIGGER_NUM-1:0] wp_hit_vec;        // EX 级（访存地址）
logic                    trigger_hit_data;  // 观察点命中（dpc 需取 EX 级指令 PC）
genvar ti;
generate
    for (ti = 0; ti < `TRIGGER_NUM; ti++) begin : gen_trigger
        // 硬件断点：取指地址匹配
        assign trigger_hit_vec[ti] = trigger_exec_en[ti] & (inst_addr_if == trigger_addr[ti*DATA_WIDTH +: DATA_WIDTH]);
        // 数据观察点：load/store 有效地址匹配，读/写类型 + 访问宽度过滤（sizelo：0=any 1=8b 2=16b 3=32b）
        assign wp_hit_vec[ti] = access_en_ex
                              & ((trigger_load_en[ti] & ~access_wr_ex) | (trigger_store_en[ti] & access_wr_ex))
                              & ((trigger_size[ti*2 +: 2] == 2'd0) || (trigger_size[ti*2 +: 2] == (access_func3_ex[1:0] + 2'd1)))
                              & (access_addr_ex == trigger_addr[ti*DATA_WIDTH +: DATA_WIDTH]);
    end
endgenerate
assign trigger_hit      = |trigger_hit_vec | |wp_hit_vec;
assign trigger_hit_data = |wp_hit_vec;

// 观察点命中时流水线停在 EX，dpc 取访存指令自身；其余 halt（haltreq/trigger/step）取 inst_addr_if。
assign ebreak_halt = id_ebreak & dbg_ebreakm;
assign dbg_dpc     = ebreak_halt ? inst_addr_id
                   : trigger_hit_data ? inst_addr_ex   // 观察点命中：流水线停在 EX，dpc = 访存指令自身
                   : inst_addr_if;                     // 普通 halt/断点：dpc = 取指地址

logic   [DATA_WIDTH-1:0]    access_wdata_ex;
logic   [ALIGN_BYTES-1:0]   access_wmask_ex;
logic                       reg_rd_wen_ex;
logic   [REG_ADDR_WIDTH-1:0]reg_rd_waddr_ex;
logic   [DATA_WIDTH-1:0]    reg_rd_wdata_ex;

logic   [REG_ADDR_WIDTH-1:0]reg_rs1_raddr_ex;
logic   [REG_ADDR_WIDTH-1:0]reg_rs2_raddr_ex;
logic                       wfi_req;
logic                       mret_req;
logic                       is_nop_ex;
logic                       is_fence_i_ex;
logic                       branch_taken_ex;
logic   [ADDR_WIDTH-1:0]    branch_target_ex;
logic   [1:0]               branch_inst_type_ex;
logic                       branch_req_ex;
logic                       branch_predict_success_ex;
logic                       push_ras_ex;
logic                       pop_ras_ex;


//CSR
logic                       csr_en;
logic   [CSR_ADDR_WIDTH-1:0]csr_addr;
logic   [DATA_WIDTH-1:0]    csr_rdata;
logic   [DATA_WIDTH-1:0]    csr_wdata;

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
logic   [DATA_WIDTH-1:0]    dtcm_rdata;
logic                       dtcm_sel;
logic                       bus_sel;
logic                       dtcm_rvalid;
logic                       bus_rvalid;
wire                        cpu_bus_transfer;   // CPU 总线请求（SBA 外设访问时覆盖）
// MEM/WB bypass for bus loads (reg_rd_wen/addr from EX stage, bypassing EX/MEM)
logic                       reg_rd_wen_selected_mem;
logic   [REG_ADDR_WIDTH-1:0]reg_rd_waddr_selected_mem;
// Bus load rd latch: 在 bus_transfer 时刻锁存 lw 的目标寄存器
// 解决 id_ex_flush 刷掉 EX 后总线返回时不知写哪的问题
logic   [REG_ADDR_WIDTH-1:0]  bus_load_waddr;

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        bus_load_waddr <= #1 '0;
    else if (cpu_bus_transfer)
        bus_load_waddr <= #1 reg_rd_waddr_ex;
end

// Bus 访问方向/地址锁存：bus_transfer 时刻锁存，解决总线 stall 期间
// ex_mem_flush 清掉 access_wr_ex/access_addr_ex 后，返回时无法判断读写方向和地址的问题
logic                       bus_write_q;
logic   [ADDR_WIDTH-1:0]    bus_addr_q;

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        bus_write_q <= #1 1'b0;
        bus_addr_q  <= #1 '0;
    end else if (cpu_bus_transfer) begin
        bus_write_q <= #1 access_wr_ex;
        bus_addr_q  <= #1 access_addr_ex;
    end
end

// 总线错误检测：仅 CPU 总线事务有效（SBA 事务由 DM 侧 sba_error 处理）
// （DECERR=2'b11 来自超时/无响应，SLVERR=2'b10 来自从机）
wire  sba_bus_active;      // SBA 外设总线访问进行中（在 SBA 译码区 assign）
wire  bus_tran_done_cpu;   // CPU 视角总线完成（屏蔽 SBA 事务）
assign bus_tran_done_cpu = bus_tran_done && ~sba_bus_active;
logic bus_error;
assign bus_error = bus_tran_done_cpu && (bus_resp != 2'b00);

// =========================================================================
// 异常编码（统一在顶层完成，子模块只报 1-bit 条件）
// 约定：无异常 = {31{1'b1}}（bit[30]=1 为哨兵），有效异常码 bit[30]=0
// =========================================================================
// IF 级：指令访问错误 > 指令地址未对齐
assign exception_code_if = if_access_fault  ? {{DATA_WIDTH-5{1'b0}}, 4'd1}
                         : if_addr_misalign ? {{DATA_WIDTH-5{1'b0}}, 4'd0}
                         : {DATA_WIDTH-1{1'b1}};
assign exception_val_if  = inst_addr_if;

// ID 级：非法指令 > ecall > ebreak
assign exception_code_id = id_illegal_inst ? {{DATA_WIDTH-5{1'b0}}, 4'd2}
                         : id_ecall        ? {{DATA_WIDTH-5{1'b0}}, (priv_mode == 2'b00) ? 4'd8 : 4'd11}
                         // ebreakm=1 时 ebreak 进入 debug 模式（mtvec 陷阱被抑制）
                         : (id_ebreak && !ebreak_halt) ? {{DATA_WIDTH-5{1'b0}}, 4'd3}
                         : {DATA_WIDTH-1{1'b1}};
assign exception_val_id  = id_illegal_inst ? inst_id : 'h0;

// EX 级：bus_error > 访存非法 > 访存未对齐 > 非法 CSR
// bus_error 时 mtval 填锁存地址 bus_addr_q；访存异常填 access_addr_ex；非法 CSR 填 inst_ex
assign exception_code_ex = bus_error        ? (bus_write_q ? {{DATA_WIDTH-5{1'b0}}, 4'd7}
                                                           : {{DATA_WIDTH-5{1'b0}}, 4'd5})
                         : ex_access_illegal ? (access_wr_ex ? {{DATA_WIDTH-5{1'b0}}, 4'd7}
                                                             : {{DATA_WIDTH-5{1'b0}}, 4'd5})
                         : ex_addr_misalign  ? (access_wr_ex ? {{DATA_WIDTH-5{1'b0}}, 4'd6}
                                                             : {{DATA_WIDTH-5{1'b0}}, 4'd4})
                         : ex_illegal_csr    ? {{DATA_WIDTH-5{1'b0}}, 4'd2}
                         : {DATA_WIDTH-1{1'b1}};
assign exception_val_ex  = bus_error                    ? bus_addr_q
                         : (ex_access_illegal | ex_addr_misalign) ? access_addr_ex
                         : ex_illegal_csr               ? inst_ex
                         : 'h0;


// WB
logic   [ADDR_WIDTH-1:0]    inst_addr_wb;
logic   [DATA_WIDTH-1:0]    inst_wb;
logic                       reg_rd_wen_wb;
logic   [REG_ADDR_WIDTH-1:0]reg_rd_waddr_wb;
logic   [DATA_WIDTH-1:0]    reg_rd_wdata_wb;

`ifdef DISPLAY_INST_WAVE
logic   [ADDR_WIDTH-1:0]    inst_addr_if_display;
logic   [ADDR_WIDTH-1:0]    inst_addr_id_display;
logic   [ADDR_WIDTH-1:0]    inst_addr_ex_display;
logic   [ADDR_WIDTH-1:0]    inst_addr_mem_display;
logic   [ADDR_WIDTH-1:0]    inst_addr_wb_display;
assign inst_addr_if_display = inst_addr_if;
`endif
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
assign hpm_mispredict = ~branch_predict_success_ex;
assign hpm_valid = mem_wb_valid & ~mem_wb_stall;
assign hpm_inst_type = inst_type_wb;



Pipeline_Ctrl #(
    .ADDR_WIDTH(ADDR_WIDTH),
    .DATA_WIDTH(DATA_WIDTH)
)u_Pipeline_Ctrl(
    .clk            (clk),
    .rst_n          (rst_n),
    .branch_jump_en      	(branch_jump_en_ex    ),
    .branch_jump_addr    	(branch_jump_addr_ex  ),
    .trap_jump           	(trap_jump            ),
    .trap_jump_addr      	(trap_jump_addr       ),
    .trap_jump_exc         (trap_jump_exc         ),
    .priv_mode           	(priv_mode            ),
    .waiting_int           	(waiting_int          ),
    .dbg_halt_req           (dbg_halt_req         ),
    .dbg_halted             (dbg_halted           ),
    .dbg_step               (dbg_step             ),
    .dbg_resume_pulse       (dbg_resume_req       ),
    .trigger_match          (trigger_hit          ),
    .ebreak_halt            (ebreak_halt          ),
    .sba_bus_active         (sba_bus_active       ),
    .load_use_flag       	(load_use_flag        ),
    .bus_ready    	        (bus_ready            ),
    .oitf_stall          	(oitf_stall           ),
    .reg_rd_wen_wb          (reg_rd_wen_wb        ),
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
    .oitf_flush          	(oitf_flush           ),
    .exception_inst_addr 	(exception_inst_addr  ),
    .exception_trap      	(exception_trap       ),
    .exception_code      	(exception_code       ),
    .exception_val       	(exception_val        )
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
    .reg_rd_wen_wb       	(reg_rd_wen         ),
    .reg_rd_waddr_wb     	(reg_rd_waddr       ),
    .lp_retire_valid        (oitf_retire_valid  ),
    .lp_retire_waddr        (oitf_retire_rd_addr),
    .lp_retire_wdata        (oitf_retire_rd_data),
    .alu_op1_from_id_ex 	(alu_op1_from_id_ex ),
    .alu_op2_from_id_ex 	(alu_op2_from_id_ex ),
    .reg_rs2_rdata_ex    	(reg_rs2_rdata_ex   ),
    .reg_rd_wdata_mem    	(reg_rd_wdata_mem   ),
    .reg_rd_wdata_wb     	(reg_rd_wdata_wb    ),
    .bus_sel                (bus_sel            ),
    .load_use_flag      	(load_use_flag      ),
    .alu_op1_o          	(alu_op1_forward    ),
    .alu_op2_o          	(alu_op2_forward    ),
    .access_wdata_temp   	(access_wdata_temp  ),
    .fwd_a_hit           	(fwd_a_hit          ),
    .fwd_b_hit           	(fwd_b_hit          )
);

Dynamic_Branch_Predictor #(
    .ADDR_WIDTH     (ADDR_WIDTH ),
    .DATA_WIDTH     (DATA_WIDTH ),
    .ALIGN_WIDTH    (ALIGN_WIDTH)
)u_Dynamic_Branch_Predictor(
    .clk             (clk               ),
    .rst_n           (rst_n             ),
    .stall           (pc_stall          ),
    .inst_addr       (inst_addr_if      ),
    .is_fence_i      (is_fence_i_ex     ),
    .branch_pc       (inst_addr_ex      ),  // 从 EX_MEM 寄存器输出来（与 branch_taken 对齐）
    .branch_taken    (branch_taken_ex   ),
    .branch_target   (branch_target_ex  ),
    .branch_req      (branch_req_ex     ),
    .branch_predict_success(branch_predict_success_ex),
    .branch_inst_type(branch_inst_type_ex),
    .push_ras        (push_ras_ex       ),
    .pop_ras         (pop_ras_ex        ),
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
    .predict_taken  (predict_taken_if & ~dbg_step & ~dbg_halt_req),  // debug 模式禁用预测
    .predict_target (predict_target_if),
    .stall          (pc_stall),
    .dbg_load_en    (dbg_resume_req),
    .dbg_load_addr  (dbg_pc_wdata),
    .pc             (pc),               // 下一条指令地址，给 BootROM/ITCM 读地址
    .if_addr_misalign (if_addr_misalign),
    .if_access_fault  (if_access_fault),
    .inst_addr_o    (inst_addr_if)      // 当前指令地址，给流水线
);

// 指令来源 MUX（选择信号基于 inst_addr_if = 当前取出的指令地址）
logic [DATA_WIDTH-1:0]    bootrom_inst;
logic [DATA_WIDTH-1:0]    itcm_inst;
logic                     bootrom_sel;
logic                     itcm_sel;
wire  [ADDR_WIDTH-1:0]    bootrom_rd_addr;   // BootROM read addr: sba_addr when SBA hits 0x0000 region

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
    .inst_addr      (bootrom_rd_addr),               // 提前一拍送地址
    .inst_o         (bootrom_inst)      // 同步读，下一拍输出
);

// ============================================================
// SBA (System Bus Access) 地址译码与 MUX
// CPU halt 期间调试器通过 SBA 读写 ITCM/DTCM/外设总线；BootROM(0x0000) 只读
// 译码与 CPU 一致：BOOT=0x0000, ITCM=0x0001, DTCM=0x0002, tag>=0x8000 走 AXI/APB 总线
// ============================================================
wire sba_bootrom_sel = (sba_addr[ADDR_WIDTH-1:16] == `BOOT_BASE_TAG);
wire sba_itcm_sel    = (sba_addr[ADDR_WIDTH-1:16] == `ITCM_BASE_TAG);
wire sba_dtcm_sel    = (sba_addr[ADDR_WIDTH-1:16] == `DTCM_BASE_TAG);
wire sba_bus_sel     = (sba_addr[ADDR_WIDTH-1:16] >= `BUS_BASE_ADDR);
wire sba_any_sel     = sba_bootrom_sel | sba_itcm_sel | sba_dtcm_sel | sba_bus_sel;
// BootROM read-addr mux: switch to sba_addr only for SBA read of 0x0000 (PC frozen while halted)
assign bootrom_rd_addr = (sba_req_valid && sba_bootrom_sel) ? sba_addr : pc;

// ITCM 读地址 mux：SBA 覆盖 PC
wire [ADDR_WIDTH-1:0] itcm_rd_addr = (sba_req_valid && sba_itcm_sel) ? sba_addr : pc;

// ITCM 子字写 RMW：ITCM 写口无字节使能，8/16 位写先读 word 再合并写回
logic itcm_rmw_active;   // RMW 写 phase（下一拍执行写）
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) itcm_rmw_active <= 1'b0;
    else        itcm_rmw_active <= sba_req_valid & sba_itcm_sel & sba_write & (sba_size != 3'd2);
end
// 子字写数据 lane 重排：把 sba_wdata 低字节/半字移到 be 指示的目标 lane
// （DTCM 直写 wmask、ITCM RMW 合并、外设 PSTRB 均使用该重排后的数据）
logic [DATA_WIDTH-1:0] sba_wdata_lane;
always_comb begin
    sba_wdata_lane = sba_wdata;
    if (sba_size == 3'd0) begin
        case (sba_addr[1:0])
            2'd1: sba_wdata_lane[15:8]  = sba_wdata[7:0];
            2'd2: sba_wdata_lane[23:16] = sba_wdata[7:0];
            2'd3: sba_wdata_lane[31:24] = sba_wdata[7:0];
        endcase
    end else if (sba_size == 3'd1) begin
        if (sba_addr[1]) sba_wdata_lane[31:16] = sba_wdata[15:0];
    end
end
logic [DATA_WIDTH-1:0] itcm_rmw_data;   // 读回 word 与写数据按 be 合并
always_comb begin
    itcm_rmw_data = itcm_inst;
    for (int b = 0; b < ALIGN_BYTES; b++) begin
        if (sba_be[b])
            itcm_rmw_data[b*8 +: 8] = sba_wdata_lane[b*8 +: 8];
    end
end

// ITCM 写 mux：SBA 复用 download 端口（全字直写；子字写经 RMW）
wire                    itcm_wr_en_sba   = itcm_download_en
                                         | (sba_req_valid & sba_itcm_sel & sba_write & (sba_size == 3'd2))
                                         | itcm_rmw_active;
wire [ADDR_WIDTH-1:0]  itcm_wr_addr_sba = ((sba_req_valid & sba_itcm_sel) || itcm_rmw_active) ? sba_addr : itcm_download_addr;
wire [DATA_WIDTH-1:0]  itcm_wr_data_sba = itcm_rmw_active ? itcm_rmw_data :
                                          (sba_req_valid & sba_itcm_sel & sba_write) ? sba_wdata : itcm_download_data;

// DTCM 访问 mux：SBA 覆盖 EX 级（DTCM 自带字节使能 wmask）
wire [ADDR_WIDTH-1:0]  dtcm_addr_sba  = (sba_req_valid & sba_dtcm_sel) ? sba_addr : access_addr_ex;
wire                    dtcm_wen_sba   = (sba_req_valid & sba_dtcm_sel & sba_write) ? 1'b1 :
                                          (access_wr_ex && dtcm_sel && ~(ex_mem_stall || ex_mem_flush));
wire [DATA_WIDTH-1:0]  dtcm_wdata_sba = (sba_req_valid & sba_dtcm_sel & sba_write) ? sba_wdata_lane : access_wdata_ex;
wire [ALIGN_BYTES-1:0] dtcm_wmask_sba = (sba_req_valid & sba_dtcm_sel & sba_write) ? sba_be : access_wmask_ex;

// SBA 外设总线访问：注入 CPU 总线通路（CPU halt 期间无总线活动，直接覆盖）
assign sba_bus_active = sba_req_valid & sba_bus_sel;

// SBA 响应流水线（BRAM 同步读 1 拍延迟；总线响应 = bus_tran_done）
logic        sba_req_d;
logic        sba_bootrom_d;
logic        sba_itcm_d;
logic        sba_rmw_d;      // 上一拍请求是否为 ITCM 子字写
logic        sba_bus_d;      // 上一拍请求是否为外设总线访问
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        sba_req_d  <= 1'b0;
        sba_bootrom_d <= 1'b0;
        sba_itcm_d <= 1'b0;
        sba_rmw_d  <= 1'b0;
        sba_bus_d  <= 1'b0;
    end else begin
        sba_req_d  <= sba_req_valid;
        sba_bootrom_d <= sba_bootrom_sel;
        sba_itcm_d <= sba_itcm_sel;
        sba_rmw_d  <= sba_req_valid & sba_itcm_sel & sba_write & (sba_size != 3'd2);
        sba_bus_d  <= sba_bus_sel;
    end
end
assign sba_rsp_valid = (sba_req_d & ~sba_rmw_d & ~sba_bus_d)  // TCM 直读/全字写/未映射：1 拍
                     | itcm_rmw_active                        // ITCM 子字写：RMW 写完成
                     | (sba_bus_d & bus_tran_done);           // 外设总线完成（sba_bus_d 为寄存器，避免组合环）
// rsp 拍 sba_req_valid 已被 DM 同拍拉低，总线选择用寄存器延迟 sba_bus_d
assign sba_rdata     = sba_bus_d ? bus_rdata :
                       sba_bootrom_d ? bootrom_inst :
                       sba_itcm_d ? itcm_inst : dtcm_rdata;
assign sba_error     = sba_bus_d ? (bus_resp != 2'b00)
                                 : (sba_bootrom_d & sba_write) ? 1'b1   // BootROM read-only, write returns error
                                 : ~sba_any_sel;

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
    .itcm_download_en     (itcm_wr_en_sba),
    .itcm_download_addr   (itcm_wr_addr_sba),
    .itcm_download_data   (itcm_wr_data_sba),
    .inst_addr      (itcm_rd_addr),      // SBA 时覆盖 PC
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
    .predict_target_o   (predict_target_id),
`ifdef DISPLAY_INST_WAVE
    .inst_addr_display_o(inst_addr_id_display),
`endif
    .valid_o            (if_id_valid)
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
    .reg_rs1_rdata  (reg_rs1_rdata),
    .reg_rs2_rdata  (reg_rs2_rdata),
    .alu_op1        (alu_op1_id),
    .alu_op2        (alu_op2_id),
    .imm            (imm_id),
    .access_wr      (access_wr_id),
    .access_en      (access_en_id),
    .csr_en         (csr_en_id),
    .csr_addr       (csr_addr_id),
    .is_nop         (is_nop_id),
    .is_fence_i     (is_fence_i_id),
    .branch_inst_type(branch_inst_type_id),
    .branch_req     (branch_req_id),
    .push_ras       (push_ras_id),
    .pop_ras        (pop_ras_id),
    .id_illegal_inst (id_illegal_inst),
    .id_ecall       (id_ecall),
    .id_ebreak      (id_ebreak),
    .inst_type      (inst_type_id)
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
    .reg_rd_wdata2  (oitf_retire_rd_data),
    //调试端口
    .dbg_we         (dbg_reg_we),
    .dbg_waddr      (dbg_reg_addr),
    .dbg_wdata      (dbg_reg_wdata),
    .dbg_raddr      (dbg_reg_addr),
    .dbg_rdata      (dbg_reg_rdata)
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
    .alu_op1_fwd_i  (alu_op1_forward),
    .fwd_a_hit_i    (fwd_a_hit),
    .alu_op2_fwd_i  (alu_op2_forward),
    .fwd_b_hit_i    (fwd_b_hit),
    .jump_imm_i     (jump_imm_id),
    .inst_addr_plus_4_i(inst_addr_plus_4_id),
    .reg_rs1_raddr_i(reg_rs1_raddr),
    .reg_rs2_raddr_i(reg_rs2_raddr),
    .access_wr_i    (access_wr_id),
    .access_en_i    (access_en_id),
    .csr_en_i       (csr_en_id),
    .csr_addr_i     (csr_addr_id),
    .is_nop_i         (is_nop_id),
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
    .is_nop_o         (is_nop_ex),
    .is_fence_i_o   (is_fence_i_ex),
    .branch_inst_type_o(branch_inst_type_ex),
    .branch_req_o   (branch_req_ex),
    .push_ras_o     (push_ras_ex),
    .pop_ras_o      (pop_ras_ex),
    .reg_rs1_raddr_o(reg_rs1_raddr_ex),
    .reg_rs2_raddr_o(reg_rs2_raddr_ex),
`ifdef DISPLAY_INST_WAVE
    .inst_addr_display_o(inst_addr_ex_display),
`endif
    .inst_type_i    (inst_type_id),
    .inst_type_o    (inst_type_ex),
    .valid_i        (if_id_valid),
    .valid_o        (id_ex_valid)
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
    .is_nop           	(is_nop_ex          ),
    .is_fence_i         (is_fence_i_ex      ),
    .csr_rdata        	(csr_rdata          ),
    .access_en          (access_en_ex       ),
    .access_wr         	(access_wr_ex       ),
    .alu_op1          	(alu_op1_forward    ),
    .alu_op2          	(alu_op2_forward    ),
    .reg_rs1_raddr      (reg_rs1_raddr_ex   ),
    .reg_rs2_raddr      (reg_rs2_raddr_ex   ),
    .jump_imm         	(jump_imm_ex        ),
    .inst_addr_plus_4   (inst_addr_plus_4_ex),
    .access_wdata_temp 	(access_wdata_temp  ),
    .branch_jump_en     (branch_jump_en_ex  ),
    .branch_jump_addr   (branch_jump_addr_ex),
    .ex_access_illegal  (ex_access_illegal  ),
    .ex_addr_misalign   (ex_addr_misalign   ),
    .id_ex_flush        (id_ex_flush),
    .id_ex_stall        (id_ex_stall),
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
    .branch_target      (branch_target_ex   ),
    .branch_predict_success(branch_predict_success_ex)
);
logic branch_taken_r;
logic branch_jump_addr_r;
always_ff @(posedge clk) begin
    branch_taken_r <= branch_taken_ex;
    branch_jump_addr_r <= branch_jump_addr_ex;
end
assign next_inst_addr = branch_taken_ex ? branch_target_ex : branch_taken_r ? branch_jump_addr_ex : inst_addr_id;
CSR_Reg_Access #(
    .ADDR_WIDTH     (ADDR_WIDTH),
    .DATA_WIDTH     (DATA_WIDTH),
    .CSR_ADDR_WIDTH (CSR_ADDR_WIDTH)
)u_CSR_Reg_Access(
    .clk            	(clk                ),
    .rst_n          	(rst_n              ),
    .csr_en             (csr_en             ),
    .csr_addr       	(csr_addr           ),
    .csr_wdata    	    (csr_wdata          ),
    .csr_rdata    	    (csr_rdata          ),
    .exception_inst_addr(exception_inst_addr),
    .next_inst_addr 	(next_inst_addr     ),
    .bus_ready       	(bus_ready          ),
    .oitf_stall         (oitf_stall         ),
    .wfi_req        	(wfi_req            ),
    .mret_req       	(mret_req           ),
    .exception_trap 	(exception_trap     ),
    .exception_code 	(exception_code     ),
    .exception_val  	(exception_val      ),
    .external_int   	(external_int       ),
    .software_int   	(software_int       ),
    .timer_int      	(timer_int          ),
    .mtime_shadow   	(mtime_shadow       ),
    .ex_illegal_csr     (ex_illegal_csr     ),
    .priv_mode      	(priv_mode          ),
    .trap_jump      	(trap_jump          ),
    .trap_jump_addr 	(trap_jump_addr     ),
    .trap_jump_exc         (trap_jump_exc         ),
    .waiting_int        (waiting_int        ),
    .hpm_valid          (hpm_valid          ),
    .hpm_inst_type      (hpm_inst_type      ),
    .hpm_mispredict     (hpm_mispredict),
    // Debug CSR（Abstract 通用 CSR 读写）
    .dbg_csr_we         (dbg_csr_we         ),
    .dbg_csr_addr       (dbg_csr_addr       ),
    .dbg_csr_wdata      (dbg_csr_wdata      ),
    .dbg_csr_rdata      (dbg_csr_rdata      )
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
    .access_en_i    (access_en_ex),
    .access_wr_i    (access_wr_ex),
    .inst_addr_o    (inst_addr_mem),
    .inst_o         (inst_mem),
    .access_en_o    (access_en_mem),
    .access_wr_o    (access_wr_mem),
    .reg_rd_wen_o   (reg_rd_wen_mem),
    .reg_rd_waddr_o (reg_rd_waddr_mem),
    .reg_rd_wdata_o (reg_rd_wdata_mem),
`ifdef DISPLAY_INST_WAVE
    .inst_addr_display_o(inst_addr_mem_display),
`endif
    .inst_type_i    (inst_type_ex),
    .inst_type_o    (inst_type_mem),
    .valid_i        (id_ex_valid),
    .valid_o        (ex_mem_valid)
);

Mem_Access #(
    .ADDR_WIDTH (ADDR_WIDTH),
    .DATA_WIDTH (DATA_WIDTH)
)u_Mem_Access(
    .clk                        (clk),
    .rst_n                      (rst_n),
    .ex_mem_flush               (ex_mem_flush),
    .ex_mem_stall               (ex_mem_stall),
    .access_addr                (access_addr_ex),
    .access_en                  (access_en_ex),
    .access_wr                  (access_wr_ex),
    .bus_tran_done              (bus_tran_done_cpu),
    .dtcm_rdata                 (dtcm_rdata),
    .rd_bus_data                (bus_rdata),
    .access_func3               (access_func3_ex),
    .dtcm_sel                   (dtcm_sel),
    .bus_sel                    (bus_sel),
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
    .access_addr(dtcm_addr_sba),
    .wr_en      (dtcm_wen_sba),
    .wr_data    (dtcm_wdata_sba),
    .wr_mask    (dtcm_wmask_sba),
    .dtcm_download_en (dtcm_download_en   ),
    .dtcm_download_addr(dtcm_download_addr),
    .dtcm_download_data(dtcm_download_data),
    .rd_data    (dtcm_rdata)
);

// MUX2: load data only for LOAD instructions, ALU result for everything else
// bus_rvalid 只对 load 指令选择 func3_expanded_data，非 load 指令（如 lui）固定传 ALU 结果
assign reg_rd_wdata_selected_mem = (dtcm_rvalid || bus_rvalid) ? func3_expanded_data : reg_rd_wdata_mem;

// MEM/WB reg_rd_wen/reg_rd_waddr bypass: bus loads skip EX/MEM, DTCM/ALU go through EX/MEM
// 总线错误（bus_error）时禁止写回，避免把超时返回的垃圾数据写入寄存器
assign reg_rd_wen_selected_mem   = (dtcm_rvalid || (bus_rvalid && ~bus_error)) ? 1'b1 : reg_rd_wen_mem;
assign reg_rd_waddr_selected_mem = bus_rvalid ? bus_load_waddr : reg_rd_waddr_mem;

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
    .reg_rd_wdata_o (reg_rd_wdata_wb),
`ifdef DISPLAY_INST_WAVE
    .inst_addr_display_o(inst_addr_wb_display),
`endif
    .inst_type_i    (inst_type_mem),
    .inst_type_o    (inst_type_wb),
    .valid_i        (ex_mem_valid),
    .valid_o        (mem_wb_valid)
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
    .flush          (oitf_flush),
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
    .retire_rd_wen  (oitf_retire_rd_wen)
);

// Port1 写端口：正常 WB 路径（bus_rvalid 直通否则走 MEM_WB）
assign reg_rd_wdata = reg_rd_wdata_wb;
assign reg_rd_wen   = reg_rd_wen_wb;
assign reg_rd_waddr = reg_rd_waddr_wb;

// CPU 总线请求（SBA 外设访问时覆盖，CPU halt 期间无总线活动）
assign cpu_bus_transfer = bus_sel && ~(waiting_int || oitf_stall) && ~trigger_hit;
assign bus_transfer      = sba_bus_active ? 1'b1 : cpu_bus_transfer;
assign bus_access_write  = sba_bus_active ? sba_write  : access_wr_ex;
assign bus_access_wdata  = sba_bus_active ? sba_wdata_lane : access_wdata_ex;
assign bus_access_addr   = sba_bus_active ? sba_addr   : access_addr_ex;
assign bus_access_wstrb  = sba_bus_active ? sba_be     : access_wmask_ex;

endmodule
