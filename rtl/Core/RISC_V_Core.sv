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
logic                       id_illegal_total;   // 含压缩保留编码
logic                       illegal_inst_if;    // IFU 展开器报保留编码
logic                       illegal_inst_id;
logic [ADDR_WIDTH-1:0]      fetch_word_addr_if; // 取指返回字地址（IFU req_addr，供取指数据区选）
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
logic   [DATA_WIDTH-1:0]    inst_if;    // IFU_Buffer 装配+展开后的指令（给 IF_ID）
logic                       inst_valid_if; // IFU_Buffer 本拍是否输出有效指令
logic                       fetch_wait_if; // IFU 取指字未就绪（非 stall/redirect）
logic                       is_compressed_if;
logic                       fetch_served;   // 本拍取指请求地址确实被存储器服务
logic                       predict_taken_if;
logic                       predict_taken_gated;  // IFU 门控后的预测（Zcmp 展开期仅 ret 微操作预测）
logic                       predict_spec_upd_if;  // IFU 实际发射门控（预测器 spec 更新用）
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
logic   [ADDR_WIDTH-1:0]    inst_addr_plus_len_id;  // PC+指令长度（压缩 +2 / 普通 +4）
logic                       is_compressed_id;
assign jump_imm_id          = inst_addr_id + imm_id;
assign inst_addr_plus_len_id = inst_addr_id + (is_compressed_id ? 32'd2 : 32'd4);
assign id_illegal_total     = id_illegal_inst | illegal_inst_id;

// EX
(*MAX_FANOUT =32*)logic   [ADDR_WIDTH-1:0]    inst_addr_ex;
logic   [DATA_WIDTH-1:0]    inst_ex;
logic                       predict_taken_ex;
logic   [ADDR_WIDTH-1:0]    predict_target_ex;
logic   [DATA_WIDTH-1:0]    imm_ex;
logic   [ADDR_WIDTH-1:0]    jump_imm_ex;
logic   [ADDR_WIDTH-1:0]    inst_addr_plus_len_ex;
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
logic                       apb_sel;
logic                       tcm_rvalid;
logic                       bus_rvalid;
// 非对齐拆分访问（Mem_Access FSM）
logic                       itcm_store_sel_ma;
logic                       itcm_load_sel;
logic                       itcm_lsu_access;   // EX 级访问 ITCM（load/store，取指让路）
wire                        itcm_access_active; // 未停顿的 ITCM 访问
logic                       split_misaligned;
logic                       split_active;
logic                       split_p2;
logic                       split_xfer;
logic                       split_xfer2;
logic                       split_xfer_off;
logic   [ADDR_WIDTH-1:0]    split_base;
logic   [ADDR_WIDTH-1:0]    split_addr;
logic   [ADDR_WIDTH-1:0]    split_addr_use;
logic                       split_stall;
logic                       split_wen_p1;
logic                       split_wen;
logic                       split_wr;
logic   [DATA_WIDTH-1:0]    split_wdata_p1;
logic   [ALIGN_BYTES-1:0]   split_wmask_p1;
logic   [DATA_WIDTH-1:0]    split_wdata;
logic   [ALIGN_BYTES-1:0]   split_wmask;
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
// 约定：无异常 = {31{1'b1}}（bit[30]=1 为全 1 标记），有效异常码 bit[30]=0
// =========================================================================
// 非对齐异常抑制：DTCM / 总线内存（Flash/DDR）由 Mem_Access 拆分访问透明处理（不产生异常）；
// ITCM store / BootROM / APB 外设仍按规范产生 mcause=4/6 异常
wire mem_split_ok        = dtcm_sel | (bus_sel & ~apb_sel);
wire access_misalign_ex  = ex_addr_misalign & ~mem_split_ok;
// IF 级：指令访问错误 > 指令地址未对齐
assign exception_code_if = if_access_fault  ? {{DATA_WIDTH-5{1'b0}}, 4'd1}
                         : if_addr_misalign ? {{DATA_WIDTH-5{1'b0}}, 4'd0}
                         : {DATA_WIDTH-1{1'b1}};
assign exception_val_if  = inst_addr_if;

// ID 级：非法指令 > ecall > ebreak
assign exception_code_id = id_illegal_total ? {{DATA_WIDTH-5{1'b0}}, 4'd2}
                         : id_ecall        ? {{DATA_WIDTH-5{1'b0}}, (priv_mode == 2'b00) ? 4'd8 : 4'd11}
                         // ebreakm=1 时 ebreak 进入 debug 模式（mtvec 陷阱被抑制）
                         : (id_ebreak && !ebreak_halt) ? {{DATA_WIDTH-5{1'b0}}, 4'd3}
                         : {DATA_WIDTH-1{1'b1}};
assign exception_val_id  = id_illegal_total ? inst_id : 'h0;   // 压缩保留编码 mtval 记展开值

// EX 级：bus_error > 访存非法 > 访存未对齐 > 非法 CSR
// bus_error 时 mtval 填锁存地址 bus_addr_q；访存异常填 access_addr_ex；非法 CSR 填 inst_ex
assign exception_code_ex = bus_error        ? (bus_write_q ? {{DATA_WIDTH-5{1'b0}}, 4'd7}
                                                           : {{DATA_WIDTH-5{1'b0}}, 4'd5})
                         : ex_access_illegal ? (access_wr_ex ? {{DATA_WIDTH-5{1'b0}}, 4'd7}
                                                             : {{DATA_WIDTH-5{1'b0}}, 4'd5})
                         : access_misalign_ex ? (access_wr_ex ? {{DATA_WIDTH-5{1'b0}}, 4'd6}
                                                             : {{DATA_WIDTH-5{1'b0}}, 4'd4})
                         : ex_illegal_csr    ? {{DATA_WIDTH-5{1'b0}}, 4'd2}
                         : {DATA_WIDTH-1{1'b1}};
assign exception_val_ex  = bus_error                    ? bus_addr_q
                         : (ex_access_illegal | access_misalign_ex) ? access_addr_ex
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
logic                       int_accept_kill;    // 中断接受拍同拍冲刷（CSR int_trap_jump_n）
// 中断边界：id_ex_inst_addr 为 ID_EX 顶端未执行指令的 PC，
// 中断接受时 CSR 将其锁存进 mepc，被冲刷的边界指令在 mret 后重执行
logic   [ADDR_WIDTH-1:0]    id_ex_inst_addr;
assign inst_addr_ex = id_ex_inst_addr;
logic                       ex_mem_valid;
logic                       mem_wb_valid;
logic                       hpm_valid;
// HPM：指令类型（Decoder → ID_EX → EX_MEM → MEM_WB → CSR）
logic   [2:0]               inst_type_id;
logic   [2:0]               inst_type_ex;
logic   [2:0]               inst_type_mem;
logic   [2:0]               inst_type_wb;
logic   [3:0]               hpm_inst_type;
logic                       hpm_mispredict;
// Zcmp 微操作 last 标志（IF_ID→…→MEM_WB 打拍，用于展开完成/退休判定）
logic                       zcmp_micro_last_if;
logic                       zcmp_micro_last_id;
logic                       zcmp_micro_last_ex;
logic                       zcmp_micro_last_mem;
logic                       zcmp_micro_last_wb;
logic                       zcmp_flush_any;     // IF/ID/EX/MEM 级 flush（abort 展开）
logic                       zcmp_last_retired;  // 最后一个微操作已在 WB 退休
logic                       zcmp_micro_any_if, zcmp_micro_any_id, zcmp_micro_any_ex,
                              zcmp_micro_any_mem, zcmp_micro_any_wb;
logic                       zcb_tag_if, zcb_tag_id, zcb_tag_ex, zcb_tag_mem, zcb_tag_wb;
logic                       hpm_count_ok;       // WB 架构指令有效（非 last 微操作不计）
logic   [1:0]               hpm_ext;            // 扩展标签：0 基础 / 1 Zcb / 2 B / 3 Zcmp
logic                       zcmp_busy;          // Zcmp 展开进行中（中断/调试屏蔽）
assign hpm_mispredict = ~branch_predict_success_ex;
assign hpm_valid = mem_wb_valid & ~mem_wb_stall;
// WB 级指令类别补全：Decoder 的 6 类（1 ALU/2 LOAD/3 STORE/4 BRANCH/5 JUMP/6 MULDIV）
// 之外，把 SYSTEM opcode(0x73) 细分为 CSR(7) 与系统指令(8)，fence/fence.i(0x0F)
// 归入系统(8)；其余沿用 Decoder 的 inst_type（0=OTHER 不计数）。
function automatic logic [3:0] wb_inst_cat(input logic [31:0] i,
                                          input logic [2:0]  dt);
    if (i[6:0] == 7'b1110011)
        wb_inst_cat = (i[14:12] == 3'b000) ? 4'd8 : 4'd7;   // SYSTEM/CSR
    else if (i[6:0] == 7'b0001111)
        wb_inst_cat = 4'd8;                                 // fence / fence.i
    else
        wb_inst_cat = {1'b0, dt};
endfunction
assign hpm_inst_type = wb_inst_cat(inst_wb, inst_type_wb);
// 注意：不能包含 id_ex_flush——itcm 单端口让路 / load-use 机制的 id_ex_flush
// 是"IF_ID 保持 + ID_EX 冲刷重派发"的正常流程，微操作会从 IF_ID 重新派发，
// 不是真正的 abort；真正的 abort（分支重定向/陷阱/调试/总线冲刷）都会同时
// 断言 if_id_flush 或 ex_mem_flush。
assign zcmp_flush_any    = if_id_flush | ex_mem_flush | mem_wb_flush;
assign zcmp_last_retired = zcmp_micro_last_wb & mem_wb_valid & ~mem_wb_stall;

// WB 阶段架构指令计数有效：Zcmp 非 last 微操作不计入（cm.push 整条计 1）
assign hpm_count_ok = ~zcmp_micro_any_wb | zcmp_micro_last_wb;

// WB 阶段从 inst 现算 B 扩展标签（B 指令都是原生 32 位，未展开）
function automatic logic b_ext_instr(input logic [31:0] i);
    logic [6:0] op, f7;
    logic [2:0] f3;
    op = i[6:0]; f7 = i[31:25]; f3 = i[14:12];
    if (op == 7'b0110011) begin
        unique case (f7)
            7'b0100000: b_ext_instr = (f3 == 3'b100 || f3 == 3'b110 || f3 == 3'b111); // xnor/orn/andn
            7'b0000101, 7'b0010000, 7'b0110000, 7'b0010100, 7'b0100100, 7'b0110100:
                b_ext_instr = 1'b1;   // min/max、sh*add、rol/ror、bset/orc.b、bclr/bext、binv
            7'b0000100: b_ext_instr = (f3 == 3'b100);   // zext.h
            default:    b_ext_instr = 1'b0;
        endcase
    end else if (op == 7'b0010011) begin
        unique case (f7)
            7'b0110000, 7'b0010100, 7'b0100100, 7'b0110100:
                b_ext_instr = 1'b1;   // clz/ctz/cpop/sext.*、bseti、bclri/bexti、binvi/rev8
            default:    b_ext_instr = 1'b0;
        endcase
    end else begin
        b_ext_instr = 1'b0;
    end
endfunction

assign hpm_ext = zcb_tag_wb        ? 2'd1 :
                 zcmp_micro_any_wb ? 2'd3 :
                 b_ext_instr(inst_wb) ? 2'd2 : 2'd0;





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
    .int_accept_kill       (int_accept_kill       ),
    .priv_mode           	(priv_mode            ),
    .waiting_int           	(waiting_int          ),
    .ex_access_en           (access_en_ex         ),
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
    .inst_valid_if       	(inst_valid_if        ),
    .fetch_wait_if       	(fetch_wait_if        ),
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
    .mem_split_stall        (split_stall          ),
    .itcm_data_stall        (itcm_access_active   ),
    .zcmp_busy              (zcmp_busy            ),
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
    .ALIGN_WIDTH    (1)          // 取指 16 位对齐：BTB 索引/标签区分相邻半字指令
)u_Dynamic_Branch_Predictor(
    .clk             (clk               ),
    .rst_n           (rst_n             ),
    .stall           (pc_stall          ),
    .inst_addr       (inst_addr_if      ),
    .is_compressed_if(is_compressed_if  ),
    .spec_upd_i      (predict_spec_upd_if), // 仅在实际发射指令的拍更新 spec 状态
    .is_fence_i      (is_fence_i_ex     ),
    .branch_pc       (inst_addr_ex      ),  // 从 EX_MEM 寄存器输出来（与 branch_taken 对齐）
    .branch_inst_plus_len(inst_addr_plus_len_ex),
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

IFU_Buffer #(
    .ADDR_WIDTH(ADDR_WIDTH)
)u_IFU_Buffer(
    .clk            (clk),
    .rst_n          (rst_n),
    .jump_en        (ctrl_jump_en),
    .jump_addr      (ctrl_jump_addr),
    .predict_taken  (predict_taken_if & ~dbg_step & ~dbg_halt_req),  // debug 模式禁用预测
    .predict_target (predict_target_if),
    .stall          (pc_stall),
    .dbg_load_en    (dbg_resume_req),
    .dbg_load_addr  (dbg_pc_wdata),
    .w_new          (inst),
    .fetch_served   (fetch_served),
    .zcmp_flush_any_i   (zcmp_flush_any),
    .zcmp_last_retired_i(zcmp_last_retired),
    .pc             (pc),               // 下一条指令地址，给 BootROM/ITCM 读地址
    .inst_o         (inst_if),
    .inst_valid_o   (inst_valid_if),
    .fetch_wait_o   (fetch_wait_if),
    .is_compressed_o(is_compressed_if),
    .illegal_inst_o (illegal_inst_if),
    .zcmp_micro_last_o (zcmp_micro_last_if),
    .zcmp_micro_any_o  (zcmp_micro_any_if),
    .predict_spec_upd_o(predict_spec_upd_if),
    .zcb_tag_o         (zcb_tag_if),
    .zcmp_busy_o       (zcmp_busy),
    .predict_taken_o   (predict_taken_gated),
    .if_addr_misalign (if_addr_misalign),
    .if_access_fault  (if_access_fault),
    .inst_addr_o    (inst_addr_if),     // 当前指令地址，给流水线
    .fetch_word_addr_o (fetch_word_addr_if) // 返回字地址（req_addr），供取指数据区选
);

// 指令来源 MUX：按"返回字所属请求地址"（fetch_word_addr = IFU req_addr，寄存器）选区。
// 不能用 pc：重定向拍 pc 已组合指向新目标，而 w_new 仍是旧地址的返回数据（该拍
// can_issue=0、IF_ID 被冲刷，数据本不被消费）；且 pc 依赖 EX 级 trap/branch 长组合链，
// 由此形成 pc→区选→inst_raw→展开器→zcmp_capture→预测门控→pc 的组合逻辑环（LUTLP-1），
// 并把 22ns 关键路径引入取指数据路径。req_addr 在出指令拍恒等于 pc（逐分支核对），
// 行为不变；仅重定向拍的数据值不同（被冲刷，不可见）。
logic [DATA_WIDTH-1:0]    bootrom_inst;
logic [DATA_WIDTH-1:0]    itcm_inst;
logic                     bootrom_sel;
logic                     itcm_store_sel;
logic                     bootrom_fetch_sel;  // 返回字区域：BootROM（inst 区选用）
logic                     itcm_fetch_sel;     // 返回字区域：ITCM（inst 区选用）
wire  [ADDR_WIDTH-1:0]    bootrom_rd_addr;   // BootROM read addr: sba_addr when SBA hits 0x0000 region

assign bootrom_sel   = (pc[DATA_WIDTH-1:BLOCK_SIZE_WIDTH] == `BOOT_BASE_TAG);
assign itcm_store_sel= (pc[DATA_WIDTH-1:BLOCK_SIZE_WIDTH] == `ITCM_BASE_TAG);
assign bootrom_fetch_sel = (fetch_word_addr_if[DATA_WIDTH-1:BLOCK_SIZE_WIDTH] == `BOOT_BASE_TAG);
assign itcm_fetch_sel    = (fetch_word_addr_if[DATA_WIDTH-1:BLOCK_SIZE_WIDTH] == `ITCM_BASE_TAG);

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
wire sba_itcm_store_sel    = (sba_addr[ADDR_WIDTH-1:16] == `ITCM_BASE_TAG);
wire sba_dtcm_sel    = (sba_addr[ADDR_WIDTH-1:16] == `DTCM_BASE_TAG);
wire sba_bus_sel     = (sba_addr[ADDR_WIDTH-1:16] >= `BUS_BASE_ADDR);
wire sba_any_sel     = sba_bootrom_sel | sba_itcm_store_sel | sba_dtcm_sel | sba_bus_sel;
// BootROM read-addr mux: switch to sba_addr only for SBA read of 0x0000 (PC frozen while halted)
assign bootrom_rd_addr = (sba_req_valid && sba_bootrom_sel) ? sba_addr : pc;

// ITCM 子字写 RMW：ITCM 写口无字节使能，8/16 位写先读 word 再合并写回
logic itcm_rmw_active;   // RMW 写 phase（下一拍执行写）

// ITCM 单端口读/写地址 mux：SBA（含 RMW 写相位） > LSU load/store（仅访问首拍） > 取指 PC
// 注意：CORE_TEST 共享窗口（ITCM/DTCM 同 tag）下 load 由 DTCM 服务，不占 ITCM 读口，无需让路；
// store 因镜像写 ITCM 仍需让路。正常配置（ITCM/DTCM 分址）load/store 均让路。
assign itcm_lsu_access = (itcm_store_sel_ma | itcm_load_sel) & ~(itcm_load_sel & dtcm_sel);
// 未停顿的 ITCM 访问（电平）：每个访问在 EX 的未停顿拍都占用单端口；
// 停顿（ex_mem_stall/flush）期间不占端口
assign itcm_access_active = itcm_lsu_access & ~(ex_mem_stall | ex_mem_flush);
wire [ADDR_WIDTH-1:0] itcm_rd_addr = ((sba_req_valid && sba_itcm_store_sel) || itcm_rmw_active) ? sba_addr :
                                      itcm_access_active ? access_addr_ex :
                                      pc;

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) itcm_rmw_active <= 1'b0;
    else        itcm_rmw_active <= sba_req_valid & sba_itcm_store_sel & sba_write & (sba_size != 3'd2);
end
// 取指请求是否被服务：BootROM/ITCM 读口未被 SBA / LSU / RMW 写相位抢占
assign fetch_served = bootrom_sel    ? ~(sba_req_valid & sba_bootrom_sel)
                    : itcm_store_sel ? ~(itcm_access_active
                                       | (sba_req_valid & sba_itcm_store_sel)
                                       | itcm_rmw_active)
                    : 1'b0;
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

// ITCM 写 mux：SBA 全字直写 / 子字 RMW，CPU store 按字节写（自修改代码）；
// UART 下载走 ITCM 模块内部 download 端口（模块内优先，与 DTCM 一致）
wire [ALIGN_BYTES-1:0] itcm_wr_en_sba = ((sba_req_valid & sba_itcm_store_sel & sba_write & (sba_size == 3'd2)) ? {ALIGN_BYTES{1'b1}} : '0)
                                       | (itcm_rmw_active ? sba_be : '0);
// CPU store 写使能：itcm_store_sel_ma 为目标译码，未停顿的访问拍写（每个访问一拍）；
// 非对齐 ITCM store 将抛异常，先抑制写，避免 trap 前污染指令内存
wire [ALIGN_BYTES-1:0] itcm_wr_en_cpu  = (itcm_store_sel_ma && itcm_access_active && ~access_misalign_ex) ? access_wmask_ex : '0;
wire [ALIGN_BYTES-1:0] itcm_wr_en       = itcm_wr_en_cpu | itcm_wr_en_sba;
wire [DATA_WIDTH-1:0]  itcm_wr_data     = itcm_wr_en_cpu ? access_wdata_ex :
                                          itcm_rmw_active ? itcm_rmw_data :
                                          (sba_req_valid & sba_itcm_store_sel & sba_write) ? sba_wdata : '0;

// DTCM 访问 mux：SBA 覆盖 EX 级（DTCM 自带字节使能 wmask）
// 端口地址保持：rd_data 每拍跟踪端口地址，而端口在
// 非访存拍可能在地址端口出现后续指令的无效 ALU 结果；tcm_rvalid 按"stall 期间保持"设计跨越
// 多拍消费数据，若消费窗口内 rd_data 被其他地址的数据覆盖（例如栈填充值），会导致错误写回。
// 非真实访问拍冻结端口为上一访问地址，读数据即保持正确（Reg 分支与 BRAM douta 行为一致）。
wire [ADDR_WIDTH-1:0]  dtcm_addr_next  = (sba_req_valid & sba_dtcm_sel) ? sba_addr :
                                         split_active ? split_addr_use : access_addr_ex;
wire                   dtcm_port_upd   = (sba_req_valid & sba_dtcm_sel) || split_active
                                       || (access_en_ex && dtcm_sel && ~(ex_mem_stall || ex_mem_flush));
logic [ADDR_WIDTH-1:0] dtcm_port_addr_q;
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        dtcm_port_addr_q <= '0;
    else if (dtcm_port_upd)
        dtcm_port_addr_q <= dtcm_addr_next;
end
wire [ADDR_WIDTH-1:0]  dtcm_addr_sba  = dtcm_port_upd ? dtcm_addr_next : dtcm_port_addr_q;
wire                    dtcm_wen_sba   = (sba_req_valid & sba_dtcm_sel & sba_write) ? 1'b1 :
                                          split_wen_p1 ? 1'b1 :
                                          split_wen ? 1'b1 :
                                          (access_wr_ex && dtcm_sel && ~(ex_mem_stall || ex_mem_flush) && ~split_misaligned);
wire [DATA_WIDTH-1:0]  dtcm_wdata_sba = (sba_req_valid & sba_dtcm_sel & sba_write) ? sba_wdata_lane :
                                         split_wen_p1 ? split_wdata_p1 :
                                         split_wen ? split_wdata : access_wdata_ex;
wire [ALIGN_BYTES-1:0] dtcm_wmask_sba = (sba_req_valid & sba_dtcm_sel & sba_write) ? sba_be :
                                         split_wen_p1 ? split_wmask_p1 :
                                         split_wen ? split_wmask : access_wmask_ex;

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
        sba_itcm_d <= sba_itcm_store_sel;
        sba_rmw_d  <= sba_req_valid & sba_itcm_store_sel & sba_write & (sba_size != 3'd2);
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
    .itcm_access_addr     (itcm_rd_addr),
    .itcm_wr_en           (itcm_wr_en),
    .itcm_wr_data         (itcm_wr_data),
    .itcm_inst            (itcm_inst),
    .itcm_download_en     (itcm_download_en),
    .itcm_download_addr   (itcm_download_addr),
    .itcm_download_data   (itcm_download_data)
);

// 指令选择：BootROM → ITCM → NOP（非本地地址，未来走总线取指时扩展）
`ifdef XILINX
assign inst = bootrom_fetch_sel ? bootrom_inst :
              itcm_fetch_sel    ? itcm_inst    :
              `INST_NOP;
`else
// 若取出的指令含不定态 X，替换为 NOP 防止 X 传播
assign inst = bootrom_fetch_sel ? ($isunknown(bootrom_inst) ? `INST_NOP : bootrom_inst) :
              itcm_fetch_sel    ? ($isunknown(itcm_inst)    ? `INST_NOP : itcm_inst)    :
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
    .inst_i             (inst_if),
    .is_compressed_i    (is_compressed_if),
    .illegal_inst_i     (illegal_inst_if),
    .zcmp_micro_last_i  (zcmp_micro_last_if),
    .zcmp_micro_any_i   (zcmp_micro_any_if),
    .zcb_tag_i          (zcb_tag_if),
    .predict_taken_i    (predict_taken_gated),
    .predict_target_i   (predict_target_if),
    .inst_addr_o        (inst_addr_id),
    .inst_o             (inst_id),
    .is_compressed_o    (is_compressed_id),
    .illegal_inst_o     (illegal_inst_id),
    .zcmp_micro_last_o  (zcmp_micro_last_id),
    .zcmp_micro_any_o   (zcmp_micro_any_id),
    .zcb_tag_o          (zcb_tag_id),
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
 .inst_addr_plus_len_i(inst_addr_plus_len_id),
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
    .inst_addr_o    (id_ex_inst_addr),
    .inst_o         (inst_ex),
    .predict_taken_o(predict_taken_ex),
    .predict_target_o(predict_target_ex),
    .alu_op1_o      (alu_op1_from_id_ex),
    .alu_op2_o      (alu_op2_from_id_ex),
    .imm_o          (imm_ex),
    .jump_imm_o     (jump_imm_ex),
 .inst_addr_plus_len_o(inst_addr_plus_len_ex),
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
    .zcmp_micro_last_i (zcmp_micro_last_id),
    .zcmp_micro_last_o (zcmp_micro_last_ex),
    .zcmp_micro_any_i  (zcmp_micro_any_id),
    .zcmp_micro_any_o  (zcmp_micro_any_ex),
    .zcb_tag_i         (zcb_tag_id),
    .zcb_tag_o         (zcb_tag_ex),
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
 .inst_addr_plus_len (inst_addr_plus_len_ex),
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
logic [ADDR_WIDTH-1:0] branch_jump_addr_r;
always_ff @(posedge clk) begin
    branch_taken_r <= branch_taken_ex;
    branch_jump_addr_r <= branch_jump_addr_ex;
end
// 分支目标保持：taken 分支重定向后，IFU 装配目标指令（跨字 32 位 / 重新取指）需要
// 1~2 拍，期间 IF_ID 已被冲刷（if_id_valid=0），inst_addr_id 残留的是被冲掉的顺延
// 指令地址。若中断恰好在这段窗口采样，mepc 会锁存残留地址（如 c.j 落回其顺延函数）。
// branch_taken_r 只覆盖 1 拍，不足；这里把跳转目标保持到"目标指令真正进入 ID"再清除，
// 使 mepc 采样始终能取到正确的恢复点。
logic                       branch_taken_hold;
logic [ADDR_WIDTH-1:0]      branch_target_hold;
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        branch_taken_hold  <= 1'b0;
        branch_target_hold <= 'h0;
    end else if (branch_taken_ex) begin
        branch_taken_hold  <= 1'b1;
        branch_target_hold <= branch_target_ex;
    end else if (if_id_valid) begin
        // 目标（或其后继）已进入 ID，恢复点由 inst_addr_id 提供
        branch_taken_hold  <= 1'b0;
    end
end
// 中断保存 mepc 时恢复点选取：
//   1) 本拍 EX 有 taken 分支（branch_taken_ex=1）→ 用其跳转目标 branch_target_ex；
//   2) 上一拍 EX 有 taken 分支、本拍该分支已离开 EX/被冲刷（如 ret/jalr 在 EX 停留
//      两拍、c.j 后 fetch_wait）→ 必须用寄存一拍的 branch_jump_addr_r。本拍组合值
//      branch_jump_addr_ex 会随 branch_taken 清零退化成 inst_addr_plus_len（顺延
//      地址），branch_jump_addr_r 锁存的是分支真实目标，不受本拍冲刷影响；
//   3) 重定向后目标尚未进入 ID（跨字装配/重新取指窗口，IF_ID 无效）→ 用保持的
//      branch_target_hold，避免锁存被冲刷掉的顺延指令地址；
//   4) 否则取 ID 阶段指令地址 inst_addr_id。
assign next_inst_addr = branch_taken_ex ? branch_target_ex
                      : branch_taken_r ? branch_jump_addr_r
                      : branch_taken_hold ? branch_target_hold
                      : inst_addr_id;
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
    .id_ex_inst_addr	(id_ex_inst_addr    ),
    .id_ex_inst_valid	(id_ex_valid        ),
    .branch_en_ex   	({branch_jump_en_ex, branch_req_ex}),
    .int_accept_kill	(int_accept_kill    ),
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
    .hpm_count_ok       (hpm_count_ok       ),
    .hpm_oitf_retire    (oitf_retire_valid  ),
    .hpm_ext            (hpm_ext            ),
    .hpm_stall_load_use (load_use_flag      ),
    .hpm_stall_oitf     (oitf_stall         ),
    .hpm_stall_fetch    (fetch_wait_if      ),
    .zcmp_busy          (zcmp_busy          ),
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
    .zcmp_micro_last_i (zcmp_micro_last_ex),
    .zcmp_micro_last_o (zcmp_micro_last_mem),
    .zcmp_micro_any_i  (zcmp_micro_any_ex),
    .zcmp_micro_any_o  (zcmp_micro_any_mem),
    .zcb_tag_i         (zcb_tag_ex),
    .zcb_tag_o         (zcb_tag_mem),
    .valid_i        (id_ex_valid),
    .valid_o        (ex_mem_valid)
);

Mem_Access #(
    .ADDR_WIDTH     (ADDR_WIDTH),
    .DATA_WIDTH     (DATA_WIDTH),
    .ALIGN_WIDTH    (ALIGN_WIDTH),
    .ALIGN_BYTES    (ALIGN_BYTES)
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
    .itcm_rdata                 (itcm_inst),
    .rd_bus_data                (bus_rdata),
    .access_func3               (access_func3_ex),
    .access_wdata_raw           (access_wdata_temp),
    .dtcm_sel                   (dtcm_sel),
    .bus_sel                    (bus_sel),
    .apb_sel                    (apb_sel),
    .itcm_store_sel                   (itcm_store_sel_ma),
    .itcm_load_sel              (itcm_load_sel),
    .split_misaligned           (split_misaligned),
    .split_active               (split_active),
    .split_p2                   (split_p2),
    .split_xfer                 (split_xfer),
    .split_xfer2                (split_xfer2),
    .split_xfer_off             (split_xfer_off),
    .split_base                 (split_base),
    .split_addr                 (split_addr),
    .split_addr_use             (split_addr_use),
    .split_stall                (split_stall),
    .split_wen_p1               (split_wen_p1),
    .split_wen                  (split_wen),
    .split_wr                   (split_wr),
    .split_wdata_p1             (split_wdata_p1),
    .split_wmask_p1             (split_wmask_p1),
    .split_wdata                (split_wdata),
    .split_wmask                (split_wmask),
    .func3_expanded_data        (func3_expanded_data),
    .tcm_rvalid                 (tcm_rvalid),
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
assign reg_rd_wdata_selected_mem = (tcm_rvalid || bus_rvalid) ? func3_expanded_data : reg_rd_wdata_mem;

// MEM/WB reg_rd_wen/reg_rd_waddr bypass: bus loads skip EX/MEM, DTCM/ALU go through EX/MEM
// 总线错误（bus_error）时禁止写回，避免把超时返回的无效数据写入寄存器。
assign reg_rd_wen_selected_mem   = (tcm_rvalid || (bus_rvalid && ~bus_error)) ? 1'b1 : reg_rd_wen_mem;
// 非对齐拆分期间 EX_MEM 被 mem_split_stall 保持，rd 仍有效，无需走 bus_load_waddr 旁路
assign reg_rd_waddr_selected_mem = (bus_rvalid && ~split_active) ? bus_load_waddr : reg_rd_waddr_mem;

`ifndef SYNTHESIS
// ===== SVA：访存一致性 =====
// 约定：tcm_rvalid 延伸（连续 ≥2 拍）期间，若 EX 级仍是同一条访存指令
// （inst_ex 不变 = 流水线停顿持有该访问），则 DTCM 端口地址必须稳定——
// 消费窗口内端口不得漂移（dtcm_port_addr_q 端口保持固化此约定）。
// 背靠背不同 load（inst_ex 变化、rvalid 连续服务两条 load）是合法流，
// 端口按新访问切换，不在本断言约束内。
property p_rv_port_stable;
    @(posedge clk) disable iff (!rst_n)
    (tcm_rvalid && $past(tcm_rvalid) && (inst_ex == $past(inst_ex))
     ) |-> $stable(dtcm_addr_sba);
endproperty
a_rv_port_stable: assert property (p_rv_port_stable)
    else $error("[SVA][CORE] 同指令 rvalid 延伸拍端口地址漂移: inst=%h port=%h", inst_ex, dtcm_addr_sba);
`endif

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
    .zcmp_micro_last_i (zcmp_micro_last_mem),
    .zcmp_micro_last_o (zcmp_micro_last_wb),
    .zcmp_micro_any_i  (zcmp_micro_any_mem),
    .zcmp_micro_any_o  (zcmp_micro_any_wb),
    .zcb_tag_i         (zcb_tag_mem),
    .zcb_tag_o         (zcb_tag_wb),
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
// 非对齐拆分访问由 Mem_Access FSM 直接驱动：检测拍（IDLE）不发总线请求，
// P1/P2 分别访问 base / base+4（地址/写数据/字节使能全部由 FSM 锁存值驱动）
// 非对齐 APB 访问将抛 misaligned 异常：不发总线事务，避免 trap 前对外设产生副作用
assign cpu_bus_transfer = bus_sel && ~(waiting_int || oitf_stall) && ~trigger_hit && ~split_misaligned && ~access_misalign_ex;
assign bus_transfer      = sba_bus_active ? 1'b1 : (split_xfer && ~split_xfer_off) ? 1'b1 : cpu_bus_transfer;
assign bus_access_write  = sba_bus_active ? sba_write  : split_xfer ? split_wr   : access_wr_ex;
assign bus_access_wdata  = sba_bus_active ? sba_wdata_lane : split_xfer ? (split_xfer2 ? split_wdata : split_wdata_p1) : access_wdata_ex;
assign bus_access_addr   = sba_bus_active ? sba_addr   : split_xfer ? split_addr_use : access_addr_ex;
assign bus_access_wstrb  = sba_bus_active ? sba_be     : split_xfer ? (split_xfer2 ? split_wmask : split_wmask_p1) : access_wmask_ex;

endmodule
