`include "./../SoC_Config.sv"
`include "./../RV32_inst_Define.sv"
`ifndef FORMAL
timeunit 1ns;
timeprecision 1ps;
`endif
module CSR_Reg_Access #(
    parameter ADDR_WIDTH = `ADDR_WIDTH,
    parameter DATA_WIDTH = `DATA_WIDTH,
    parameter CSR_ADDR_WIDTH = `CSR_ADDR_WIDTH
)(
    input   logic                           clk,
    input   logic                           rst_n,
    input   logic                           csr_en,
    input   logic   [CSR_ADDR_WIDTH-1:0]    csr_addr,
    input   logic   [DATA_WIDTH-1:0]        csr_wdata,
    output  logic   [DATA_WIDTH-1:0]        csr_rdata,
    // Debug CSR 访问（DM 抽象命令，仅 CPU halted 时活跃）
    input   logic                           dbg_csr_we,
    input   logic   [CSR_ADDR_WIDTH-1:0]    dbg_csr_addr,
    input   logic   [DATA_WIDTH-1:0]        dbg_csr_wdata,
    output  logic   [DATA_WIDTH-1:0]        dbg_csr_rdata,
// from ctrl
    input   logic   [ADDR_WIDTH-1:0]        exception_inst_addr,
    input   logic   [ADDR_WIDTH-1:0]        next_inst_addr,//IF/ID或者jump_addr
    input   logic                           bus_ready,
    input   logic                           oitf_stall,

// from EX
    input   logic                           wfi_req,
    input   logic                           mret_req,
// from exception
    input   logic                           exception_trap,
    input   logic   [DATA_WIDTH-2:0]        exception_code,
    input   logic   [DATA_WIDTH-1:0]        exception_val,
// from interrupt(CLINT/PLIC)
    input                                   external_int,
    input                                   software_int,
    input                                   timer_int,
    input   logic   [ADDR_WIDTH-1:0]        id_ex_inst_addr,// ID_EX 边界指令 PC（中断接受 mepc 源）
    input   logic                           id_ex_inst_valid,// ID_EX 持有有效指令（接受门控）
    input   logic [1:0]                     branch_en_ex,// bit0=EX 级分支未决，bit1=EX_MEM 重定向拍（均推迟中断接受）
    input   logic   [2*DATA_WIDTH-1:0]      mtime_shadow,// 只读影子
// to EX
    output  logic                           ex_illegal_csr,
// to ctrl
    output  logic   [1:0]                   priv_mode,//特权模式 0：U；  1：S；  3：M
    (* MAX_FANOUT = 16 *)output  logic                           trap_jump,
    output  logic   [DATA_WIDTH-1:0]        trap_jump_addr,
    output  logic                           trap_jump_exc, // exception/mret only (no interrupt), for single-step drain
    output  logic                           int_accept_kill, // 中断接受拍脉冲（=int_trap_jump_n）：同拍冲刷 IF_ID/ID_EX，边界指令死在 ID_EX
    output  logic                           waiting_int,

    input   logic                           hpm_valid,
    input   logic   [3:0]                   hpm_inst_type,
    input   logic                           hpm_mispredict,
    input   logic                           hpm_count_ok,   // WB 架构指令有效（Zcmp 微操作排除）
    input   logic                           hpm_oitf_retire, // OITF 退休拍（MUL/DIV 架构提交点，每条恰一次）
    input   logic   [1:0]                   hpm_ext,        // 扩展标签：0基础/1Zcb/2B/3Zcmp
    // 停顿原因周期计数（周期型：与 hpm_valid 无关，仅受 mcountinhibit 门控）
    input   logic                           hpm_stall_load_use, // load-use 冒险停顿拍
    input   logic                           hpm_stall_oitf,     // OITF 乘除等待拍
    input   logic                           hpm_stall_fetch,    // 取指未就绪气泡拍
    input   logic                           zcmp_busy       // Zcmp 展开中（屏蔽中断）
// to CLINT
);

logic   illegal_inst_csr;
assign  ex_illegal_csr = illegal_inst_csr;
//机器陷阱配置
logic   [DATA_WIDTH-1:0]    mstatus;//状态0x300
logic   [DATA_WIDTH-1:0]    mie;//中断使能0x304
logic   [DATA_WIDTH-1:0]    mtvec;//中断向量（异常处理程序基地址）0x305

//机器陷阱处理程序
logic   [DATA_WIDTH-1:0]    mepc;//异常PC
logic   [DATA_WIDTH-1:0]    mcause;//异常原因
logic   [DATA_WIDTH-1:0]    mtval;//错误地址或命令
logic   [DATA_WIDTH-1:0]    mip;//中断挂起
logic   [DATA_WIDTH-1:0]    mscratch;//机器模式 trap 暂存（0x340，RT-Thread 中断栈/上下文切换用）

//机器计数器/计时器
logic   [2*DATA_WIDTH-1:0]  mcycle;
logic   [2*DATA_WIDTH-1:0]  minstret;
logic   [DATA_WIDTH-1:0]    mcountinhibit;
logic   [DATA_WIDTH-1:0]    mcounterclr;

always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        mcycle <= #1 'h0;
    else if(mcounterclr[0])
        mcycle <= #1 'h0;
    else if(mcountinhibit[0])
        mcycle <= #1 mcycle;
    else
        mcycle <= #1 mcycle + 'h1;
end

always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        minstret <= #1 'h0;
    else if(mcounterclr[2])
        minstret <= #1 'h0;
    else if(mcountinhibit[2])
        minstret <= #1 minstret;
    else if ((hpm_valid && hpm_count_ok && hpm_inst_type != 4'd6) || hpm_oitf_retire)
        // 2026-09-18 修正：MUL/DIV 的架构提交点在 OITF 退休（port2 写回），
        // 主流水线 WB 影子会被 RAW 停顿重派发冲掉（实测 20 条 mul 仅 6 条影子
        // 到达 WB）——影子(MULDIV 类)不再计数，改由 hpm_oitf_retire 恰好计一次。
        // 双增量：主流水线退休与 OITF 退休同拍时各计一条（minstret 每拍可 +2）
        minstret <= #1 minstret
                  + ((hpm_valid && hpm_count_ok && hpm_inst_type != 4'd6) ? 'h1 : 'h0)
                  + (hpm_oitf_retire ? 'h1 : 'h0);
end

// HPM 计数器（64位，标准地址 mhpmcounter3-17 = 0xB03-0xB11，高半 0xB83-0xB91）
// 计数门控 = mcountinhibit（对齐规范/Ibex/CVA6：复位全 0 即计数，软件按需停）；
// 清零 = mcounterclr（0xBC0 按位写 1）。计数器地址 = 标准 mhpmcounter3-17（0xB03-0xB11）
//   mhp_counter3 (ALU)      0
//   mhp_counter4 (LOAD)     1
//   mhp_counter5 (STORE)    2
//   mhp_counter6 (BRANCH)   3
//   mhp_counter7 (JUMP)     4
//   mhp_counter8 (MULDIV)   5
//   mhp_counter9 (MISPREDICT) 6
//   mhp_counter10 (Zcb)       7
//   mhp_counter11 (B 扩展)    8
//   mhp_counter12 (Zcmp)      9
//   mhp_counter13 (CSR)      10
//   mhp_counter14 (SYSTEM)   11
// WB 级指令类型: 0:OTHER 1:ALU 2:LOAD 3:STORE 4:BRANCH 5:JUMP 6:MULDIV
//               7:CSR 8:SYSTEM(ecall/ebreak/mret/wfi/fence)
logic   [2*DATA_WIDTH-1:0]  mhpmcounter[15];  // [0-11] 指令类计数 + [12-14] 停顿周期计数

generate
    genvar i;
    for (i = 0; i < 5; i = i + 1) begin
        always_ff @(posedge clk or negedge rst_n) begin
            if(!rst_n) begin
                mhpmcounter[i] <= #1 'h0;
            end
            else if(mcounterclr[i+3]) begin
                mhpmcounter[i] <= #1 'h0;
            end
            else if(mcountinhibit[i+3]) begin
                mhpmcounter[i] <= #1 mhpmcounter[i];
            end
            else if (hpm_valid && hpm_count_ok && hpm_inst_type == i+1) begin
                mhpmcounter[i] <= #1 mhpmcounter[i] + 'h1;
            end
        end
    end
endgenerate

// MULDIV 计数（mhpmcounter8 = 0xB08，mcountinhibit/clr 位 8）
// 2026-09-18 修正：改在 OITF 退休拍计数（每条 MUL/DIV 恰好一次）。
// 旧实现挂在主流水线 WB 影子上——影子会被 OITF RAW 停顿的 id_ex_flush
// 重派发冲掉，实测 20 条依赖 mul 只剩 6 条影子 → 漏计 70%（板上 muldiv=29 悬案根因）。
always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n)                              mhpmcounter[5] <= #1 'h0;
    else if(mcounterclr[8])                 mhpmcounter[5] <= #1 'h0;
    else if(mcountinhibit[8])               mhpmcounter[5] <= #1 mhpmcounter[5];
    else if(hpm_oitf_retire)                mhpmcounter[5] <= #1 mhpmcounter[5] + 'h1;
end


// 分支预测失败计数器（mhpmcounter9 = 0xB09，mcountinhibit/clr 位 9）
always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n)                              mhpmcounter[6] <= #1 'h0;
    else if(mcounterclr[9])                 mhpmcounter[6] <= #1 'h0;
    else if(mcountinhibit[9])               mhpmcounter[6] <= #1 mhpmcounter[6];
    else if(hpm_valid && hpm_count_ok && (hpm_inst_type == 3'd4 || hpm_inst_type == 3'd5) && hpm_mispredict)
                                            mhpmcounter[6] <= #1 mhpmcounter[6] + 'h1;
end


// CSR 指令计数（mhpmcounter13 = 0xB0D，mcountinhibit/clr 位 13）
always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n)                              mhpmcounter[10] <= #1 'h0;
    else if(mcounterclr[13])                mhpmcounter[10] <= #1 'h0;
    else if(mcountinhibit[13])              mhpmcounter[10] <= #1 mhpmcounter[10];
    else if(hpm_valid && hpm_count_ok && hpm_inst_type == 4'd7)
                                            mhpmcounter[10] <= #1 mhpmcounter[10] + 'h1;
end

// 系统指令计数（mhpmcounter14 = 0xB0E，mcountinhibit/clr 位 14：ecall/ebreak/mret/wfi/fence）
always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n)                              mhpmcounter[11] <= #1 'h0;
    else if(mcounterclr[14])                mhpmcounter[11] <= #1 'h0;
    else if(mcountinhibit[14])              mhpmcounter[11] <= #1 mhpmcounter[11];
    else if(hpm_valid && hpm_count_ok && hpm_inst_type == 4'd8)
                                            mhpmcounter[11] <= #1 mhpmcounter[11] + 'h1;
end


// 每类扩展指令独立计数（mhpmcounter10/11/12 = 0xB0A/0xB0B/0xB0C，mcountinhibit/clr 位 10/11/12）
generate
    genvar e;
    for (e = 0; e < 3; e = e + 1) begin : gen_hpm_ext
        always_ff @(posedge clk or negedge rst_n) begin
            if(!rst_n)                              mhpmcounter[7+e] <= #1 'h0;
            else if(mcounterclr[10+e])              mhpmcounter[7+e] <= #1 mhpmcounter[7+e];
            else if(mcountinhibit[10+e])            mhpmcounter[7+e] <= #1 mhpmcounter[7+e];
            else if(hpm_valid && hpm_count_ok && hpm_ext == e+1)
                                                    mhpmcounter[7+e] <= #1 mhpmcounter[7+e] + 'h1;
        end
    end
endgenerate

// 停顿原因周期计数（mhpmcounter15/16/17 = 0xB0F/0xB10/0xB11，mcountinhibit/clr 位 15/16/17）
// 周期型计数：不与 hpm_valid 挂钩（停顿拍本就无退休），仅受 mcountinhibit 门控；
// 三者机理不同允许少量重叠，账目用 "ticks = instret + Σstall + 误预测×罚期" 核算
always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n)                              mhpmcounter[12] <= #1 'h0;
    else if(mcounterclr[15])                mhpmcounter[12] <= #1 'h0;
    else if(mcountinhibit[15])              mhpmcounter[12] <= #1 mhpmcounter[12];
    else if(hpm_stall_load_use)             mhpmcounter[12] <= #1 mhpmcounter[12] + 'h1;
end

always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n)                              mhpmcounter[13] <= #1 'h0;
    else if(mcounterclr[16])                mhpmcounter[13] <= #1 'h0;
    else if(mcountinhibit[16])              mhpmcounter[13] <= #1 mhpmcounter[13];
    else if(hpm_stall_oitf)                 mhpmcounter[13] <= #1 mhpmcounter[13] + 'h1;
end

always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n)                              mhpmcounter[14] <= #1 'h0;
    else if(mcounterclr[17])                mhpmcounter[14] <= #1 'h0;
    else if(mcountinhibit[17])              mhpmcounter[14] <= #1 mhpmcounter[14];
    else if(hpm_stall_fetch)                mhpmcounter[14] <= #1 mhpmcounter[14] + 'h1;
end


logic   int_trap;
logic   external_int_trap, software_int_trap, timer_int_trap;
logic   [DATA_WIDTH-1:0] mcause_n;
logic   [DATA_WIDTH-1:0] int_jump_addr;
logic                    int_come;
logic                    exception_jump;
logic                    int_waiting_jump;
logic                    int_trap_jump;
logic                    mret_done;      // mret 完成后的第一拍（mret_req 延迟一拍）

// 优先级：外部中断>软件中断>定时器中断
assign external_int_trap = mstatus[3] & mip[11] & mie[11];
assign software_int_trap = mstatus[3] & mip[3] & mie[3] & (!external_int_trap);
assign timer_int_trap    = mstatus[3] & mip[7] & mie[7] & (!external_int_trap & !software_int_trap);
// Zcmp 展开期间整段屏蔽中断（规范允许"实现可定义"，且保证 SP 调整/ret 尾部不被拆开）
assign int_come     = ((mip[11] & mie[11]) | (mip[3] & mie[3]) | (mip[7] & mie[7])) & ~zcmp_busy;
assign int_trap     = mstatus[3] & int_come;

assign priv_mode = mstatus[12:11];
assign exception_jump = exception_trap;
// exception/mret-only trap jump, used by the single-step drain path
assign trap_jump_exc = exception_jump | mret_req;
// 异常：本周期立即触发；中断：延迟1拍（预计算地址，指令边界响应）,但多周期指令和总线指令需要等待。
assign trap_jump = exception_jump | int_trap_jump | mret_req;

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        waiting_int <= #1 1'b0;
    end else begin
        waiting_int <= #1 wfi_req ? 1'b1 :(!int_come & waiting_int);
    end
end
always_comb begin 
    if (exception_jump)
        mcause_n = {1'b0,exception_code};
    else if (external_int_trap)
        mcause_n = {1'd1,31'd11};
    else if (software_int_trap)
        mcause_n = {1'd1,31'd3};
    else if (timer_int_trap)
        mcause_n = {1'd1,31'd7};
    else
        mcause_n = 'h0;
end

always_comb begin
    if (exception_jump)
        trap_jump_addr = {mtvec[31:2], 2'b00};              // 异常：直接模式，无加法
    else if (mret_req)
        trap_jump_addr = mepc;
    else if (int_trap_jump)
        trap_jump_addr = int_jump_addr;                      // 中断：上一周期预计算值
    else
        trap_jump_addr = 'h0;
end

logic int_trap_jump_n;
// mret 与中断重叠时禁止中断抢占锁存：mret 周期若同时锁存 int_trap_jump，
// CSR 优先级让 mret 分支赢了 mepc 写（mepc 保持旧值），但 int_trap_jump 寄存器
// 无优先级照样锁存 → 陷阱带陈旧 mepc 发出，SW_handler 会把旧 PC 存进上下文帧，
// 切回时从错误 PC 恢复。~mret_req 让中断延后一拍，在 mret 完成（PC=mepc 目标）
// 后再响应，此时 mepc 锁存为 mret 目标地址。~mret_done 为双保险
// （mret 下一拍 gap 尚未生效前的窗口，见下方 mret_gap_cnt）。
// 中断锁存必须同时满足：当前周期真实 pending（int_trap=1，保证 mcause_n 有效）。
// 仅 int_waiting_jump 残留（如 tick 已处理、mip 已清）时不得触发，
// 否则 mcause_n 落到默认 0，中断被误锁存成同步异常（mret 后尤为常见）。
// mret 后屏蔽中断 N 拍：mret 执行后流水线需要几拍（RVC 16 位取指延迟更明显）
// 才能让 IF/ID 反映 mret 目标地址。若 mret 后立即允许中断进入，
// mepc 会锁存到 IF/ID 里残留的 mret 顺延地址，恢复后跳错。
logic [2:0] mret_gap_cnt;
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        mret_gap_cnt <= #1 3'd0;
    else if (mret_req)
        mret_gap_cnt <= #1 3'd4;
    else if (mret_gap_cnt > 3'd0)
        mret_gap_cnt <= #1 mret_gap_cnt - 3'd1;
end
assign int_accept_kill = int_trap_jump_n;   // 中断接受拍脉冲：Pipeline_Ctrl 同拍冲刷，与 mepc 锁存同边沿
assign int_trap_jump_n = (int_waiting_jump | int_trap) && int_trap
                       && (bus_ready && ~oitf_stall) && ~int_trap_jump
                       && (mret_gap_cnt == 3'd0) && ~mret_req && ~mret_done
                       && id_ex_inst_valid && ~branch_en_ex[0] && ~branch_en_ex[1];

// mret 完成后的第一拍，IF/ID 流水线尚未反映 mret 跳转目标，
// next_inst_addr 仍可能是 mret 指令的下一条（旧流水线地址）。
// 此时若中断响应并锁存 mepc <= next_inst_addr，会把 mepc 写坏；
// mret 后的首次中断断点应保持为 mret 目标（mepc 现值）。
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        mret_done <= #1 1'b0;
    else
        mret_done <= #1 mret_req;
end
// 中断预计算：int_trap 有效且无异常时，锁存 trap 地址（CARRY4 不参与关键路径）
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        int_waiting_jump <= #1 1'b0;
        int_jump_addr    <= #1 'h0;
        int_trap_jump    <= #1 1'b0;
    end else begin
        int_waiting_jump <= #1 int_trap ? 1'b1 :
                                (bus_ready && ~oitf_stall) ? 1'b0 : // 只需等总线（乘除法由 OITF 兜底）
                                int_waiting_jump;
        int_trap_jump   <= #1 int_trap_jump_n;
        int_jump_addr   <= #1 int_trap_jump_n ? (mtvec[0]                         // 本周期预计算，下周期直接用
                        ? ({mtvec[31:2] + mcause_n[3:0], 2'b00}) : {mtvec[31:2], 2'b00}) : int_jump_addr;
    end
end

always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        mstatus             <= #1 'h00001800;
        mie                 <= #1 'h0;
        mtvec               <= #1 'h0;
        mepc                <= #1 'h0;
        mcause              <= #1 'h0;
        mtval               <= #1 'h0;
        mcountinhibit       <= #1 'h0;
        // mcounterclr 复位/写入已移至下方独立单拍脉冲块（避免多驱动）
        mip                 <= #1 'h0;
        mscratch            <= #1 'h0;
    end else begin//优先级：异常>外部中断>软件中断>定时器中断
        mip     <= #1 {mip[31:12],external_int,mip[10:8],timer_int,mip[6:4],software_int,mip[2:0]};
        if (exception_trap) begin//进入异常
            mcause      <= #1 mcause_n;//写入异常原因（仅陷入时更新，否则保持）
            mstatus[7]  <= #1 mstatus[3];//MPIE <- MIE
            mstatus[3]  <= #1 1'b0;//禁用全局中断
            mepc        <= #1 exception_inst_addr;//保存异常PC值
            mtval       <= #1 exception_val;//保存异常信息
        end else if (mret_req) begin//从异常返回 mepc保持不变
            mstatus[3]  <= #1 mstatus[7];//MIE <- MPIE
            mstatus[7]  <= #1 1'b1;
        end else if(int_trap_jump_n && ~mret_done) begin//int_trap_jump前一周期判断；mret 后第一拍保持 mepc（mret 目标），避免锁存旧流水线地址
            mcause      <= #1 mcause_n;//写入中断原因（仅陷入时更新，否则保持）
            mepc        <= #1 id_ex_inst_addr;//中断 mepc=边界指令自身 PC；该指令在被冲刷前从未执行，mret 后重执行
            mstatus[7]  <= #1 mstatus[3];
            mstatus[3]  <= #1 1'b0;//禁用全局中断，如果需要嵌套中断需要通过软件设置mstatus
        end else if(csr_en) begin
            case(csr_addr)
                12'h300  : mstatus          <= #1 {mstatus[31:8],csr_wdata[7],mstatus[6:4],csr_wdata[3],mstatus[2:0]};//特权模式保持M模式，写MIE和MPIE
                12'h304  : mie              <= #1 {mie[31:12],csr_wdata[11],mie[10:8],csr_wdata[7],mie[6:4],csr_wdata[3],mie[2:0]};
                12'h305  : mtvec            <= #1 csr_wdata;
                12'h320  : mcountinhibit    <= #1 csr_wdata & 32'h0003_FFFD; // WARL：仅实现位 0/2/3-17
                12'h341  : mepc             <= #1 csr_wdata;
                12'h340  : mscratch         <= #1 csr_wdata;
                // 12'h342  : mcause           <= #1 csr_wdata;
                // 12'h343  : mtval            <= #1 csr_wdata;
                // 12'h344  : mip              <= #1 csr_wdata;
                //自定义寄存器
                // 0xBC0 mcounterclr 已改为下方独立的单拍脉冲寄存器（写 1 清零语义）
                default  : ;
            endcase
        end else if (dbg_csr_we) begin
            // Debug CSR 写（DM 抽象命令，仅 CPU halted 时活跃）
            case(dbg_csr_addr)
                12'h300  : mstatus          <= #1 {mstatus[31:8],dbg_csr_wdata[7],mstatus[6:4],dbg_csr_wdata[3],mstatus[2:0]};
                12'h304  : mie              <= #1 {mie[31:12],dbg_csr_wdata[11],mie[10:8],dbg_csr_wdata[7],mie[6:4],dbg_csr_wdata[3],mie[2:0]};
                12'h305  : mtvec            <= #1 dbg_csr_wdata;
                12'h320  : mcountinhibit    <= #1 dbg_csr_wdata & 32'h0003_FFFD;
                12'h341  : mepc             <= #1 dbg_csr_wdata;
                12'h340  : mscratch         <= #1 dbg_csr_wdata;
                default  : ;
            endcase
        end
    end
end

// mcounterclr（0xBC0 写 1 清零）＝单拍脉冲：写后仅保持一拍供各计数器块采样，
// 其余拍自动归零。旧实现把 wdata 锁存成常值，清零位反而把对应计数器永久钉在 0
// （2026-09-18 stall_test 仿真实锤：load-use 链期间计数恒 0）。
logic                   mcounterclr_wr;
assign  mcounterclr_wr = (csr_en && csr_addr == 12'hbc0)       ? csr_wdata :
                         (dbg_csr_we && dbg_csr_addr == 12'hbc0) ? dbg_csr_wdata : 'h0;
always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n) mcounterclr <= #1 'h0;
    else       mcounterclr <= #1 mcounterclr_wr;
end

always_comb begin
    csr_rdata = 'h0;
    illegal_inst_csr = 1'b0;
    if (csr_en) begin
        case(csr_addr)
            12'h300  : csr_rdata = mstatus;
            12'h301  : csr_rdata = 32'h4000_1106; // misa: RV32(MXL=01) + I(bit8) + M(bit12) + C(bit2) + B(bit1)
            12'h304  : csr_rdata = mie;
            12'h305  : csr_rdata = mtvec;
            12'h320  : csr_rdata = mcountinhibit;
            12'h341  : csr_rdata = mepc;
            12'h342  : csr_rdata = mcause;
            12'h343  : csr_rdata = mtval;
            12'h344  : csr_rdata = mip;
            12'h340  : csr_rdata = mscratch;
            12'hb00  : csr_rdata = mcycle[DATA_WIDTH-1:0];
            12'hb80  : csr_rdata = mcycle[2*DATA_WIDTH-1:DATA_WIDTH];
            12'hb02  : csr_rdata = minstret[DATA_WIDTH-1:0];
            12'hb82  : csr_rdata = minstret[2*DATA_WIDTH-1:DATA_WIDTH];
            // mhpmcounter3-9 / 3h-9h (CSR 0xB03-0xB09 / 0xB83-0xB89)
            12'hb03  : csr_rdata = mhpmcounter[0][DATA_WIDTH-1:0];  // ALU
            12'hb04  : csr_rdata = mhpmcounter[1][DATA_WIDTH-1:0];  // LOAD
            12'hb05  : csr_rdata = mhpmcounter[2][DATA_WIDTH-1:0];  // STORE
            12'hb06  : csr_rdata = mhpmcounter[3][DATA_WIDTH-1:0];  // BRANCH
            12'hb07  : csr_rdata = mhpmcounter[4][DATA_WIDTH-1:0];  // JUMP
            12'hb08  : csr_rdata = mhpmcounter[5][DATA_WIDTH-1:0];  // MULDIV
        12'hb09  : csr_rdata = mhpmcounter[6][DATA_WIDTH-1:0];  // 分支预测失败
        12'hb0a  : csr_rdata = mhpmcounter[7][DATA_WIDTH-1:0];  // Zcb 指令
        12'hb0b  : csr_rdata = mhpmcounter[8][DATA_WIDTH-1:0];  // B 扩展指令
        12'hb0c  : csr_rdata = mhpmcounter[9][DATA_WIDTH-1:0];  // Zcmp 指令
        12'hb0d  : csr_rdata = mhpmcounter[10][DATA_WIDTH-1:0]; // CSR 指令
        12'hb0e  : csr_rdata = mhpmcounter[11][DATA_WIDTH-1:0]; // 系统指令
        12'hb0f  : csr_rdata = mhpmcounter[12][DATA_WIDTH-1:0]; // load-use 停顿周期
        12'hb10  : csr_rdata = mhpmcounter[13][DATA_WIDTH-1:0]; // OITF 等待周期
        12'hb11  : csr_rdata = mhpmcounter[14][DATA_WIDTH-1:0]; // 取指等待周期
            // mhpmcounter3h-9h (高32位)
            12'hb83  : csr_rdata = mhpmcounter[0][2*DATA_WIDTH-1:DATA_WIDTH];
            12'hb84  : csr_rdata = mhpmcounter[1][2*DATA_WIDTH-1:DATA_WIDTH];
            12'hb85  : csr_rdata = mhpmcounter[2][2*DATA_WIDTH-1:DATA_WIDTH];
            12'hb86  : csr_rdata = mhpmcounter[3][2*DATA_WIDTH-1:DATA_WIDTH];
            12'hb87  : csr_rdata = mhpmcounter[4][2*DATA_WIDTH-1:DATA_WIDTH];
            12'hb88  : csr_rdata = mhpmcounter[5][2*DATA_WIDTH-1:DATA_WIDTH];
        12'hb89  : csr_rdata = mhpmcounter[6][2*DATA_WIDTH-1:DATA_WIDTH];
        12'hb8a  : csr_rdata = mhpmcounter[7][2*DATA_WIDTH-1:DATA_WIDTH];
        12'hb8b  : csr_rdata = mhpmcounter[8][2*DATA_WIDTH-1:DATA_WIDTH];
        12'hb8c  : csr_rdata = mhpmcounter[9][2*DATA_WIDTH-1:DATA_WIDTH];
        12'hb8d  : csr_rdata = mhpmcounter[10][2*DATA_WIDTH-1:DATA_WIDTH];
        12'hb8e  : csr_rdata = mhpmcounter[11][2*DATA_WIDTH-1:DATA_WIDTH];
        12'hb8f  : csr_rdata = mhpmcounter[12][2*DATA_WIDTH-1:DATA_WIDTH];
        12'hb90  : csr_rdata = mhpmcounter[13][2*DATA_WIDTH-1:DATA_WIDTH];
        12'hb91  : csr_rdata = mhpmcounter[14][2*DATA_WIDTH-1:DATA_WIDTH];
            // mcounterclr（0xBC0 按位清零，自定义）：可读回防写操作被误判非法
            12'hbc0  : csr_rdata = mcounterclr;
            // time / timeh — 只读影子寄存器（mtime_shadow 来自 CLINT）
            12'hc01  : csr_rdata = mtime_shadow[DATA_WIDTH-1:0];          // time (低32位)
            12'hc81  : csr_rdata = mtime_shadow[2*DATA_WIDTH-1:DATA_WIDTH]; // timeh (高32位)
            default  : begin
                illegal_inst_csr = 1'b1;
            end
        endcase
    end
end

// Debug CSR 读（DM 抽象命令，组合输出，不受 csr_en 门控）
always_comb begin
    dbg_csr_rdata = 'h0;
    case (dbg_csr_addr)
        12'h300  : dbg_csr_rdata = mstatus;
        12'h301  : dbg_csr_rdata = 32'h4000_1106; // misa
        12'h304  : dbg_csr_rdata = mie;
        12'h305  : dbg_csr_rdata = mtvec;
        12'h320  : dbg_csr_rdata = mcountinhibit;
        12'h341  : dbg_csr_rdata = mepc;
        12'h342  : dbg_csr_rdata = mcause;
        12'h343  : dbg_csr_rdata = mtval;
        12'h344  : dbg_csr_rdata = mip;
        12'h340  : dbg_csr_rdata = mscratch;
        12'hb00  : dbg_csr_rdata = mcycle[DATA_WIDTH-1:0];
        12'hb80  : dbg_csr_rdata = mcycle[2*DATA_WIDTH-1:DATA_WIDTH];
        12'hb02  : dbg_csr_rdata = minstret[DATA_WIDTH-1:0];
        12'hb82  : dbg_csr_rdata = minstret[2*DATA_WIDTH-1:DATA_WIDTH];
        12'hb03  : dbg_csr_rdata = mhpmcounter[0][DATA_WIDTH-1:0];
        12'hb04  : dbg_csr_rdata = mhpmcounter[1][DATA_WIDTH-1:0];
        12'hb05  : dbg_csr_rdata = mhpmcounter[2][DATA_WIDTH-1:0];
        12'hb06  : dbg_csr_rdata = mhpmcounter[3][DATA_WIDTH-1:0];
        12'hb07  : dbg_csr_rdata = mhpmcounter[4][DATA_WIDTH-1:0];
        12'hb08  : dbg_csr_rdata = mhpmcounter[5][DATA_WIDTH-1:0];
        12'hb09  : dbg_csr_rdata = mhpmcounter[6][DATA_WIDTH-1:0]; // 分支预测失败
        12'hb0a  : dbg_csr_rdata = mhpmcounter[7][DATA_WIDTH-1:0];
        12'hb0b  : dbg_csr_rdata = mhpmcounter[8][DATA_WIDTH-1:0];
        12'hb0c  : dbg_csr_rdata = mhpmcounter[9][DATA_WIDTH-1:0];
        12'hb0d  : dbg_csr_rdata = mhpmcounter[10][DATA_WIDTH-1:0];
        12'hb0e  : dbg_csr_rdata = mhpmcounter[11][DATA_WIDTH-1:0];
        12'hb0f  : dbg_csr_rdata = mhpmcounter[12][DATA_WIDTH-1:0];
        12'hb10  : dbg_csr_rdata = mhpmcounter[13][DATA_WIDTH-1:0];
        12'hb11  : dbg_csr_rdata = mhpmcounter[14][DATA_WIDTH-1:0];
        12'hb83  : dbg_csr_rdata = mhpmcounter[0][2*DATA_WIDTH-1:DATA_WIDTH];
        12'hb84  : dbg_csr_rdata = mhpmcounter[1][2*DATA_WIDTH-1:DATA_WIDTH];
        12'hb85  : dbg_csr_rdata = mhpmcounter[2][2*DATA_WIDTH-1:DATA_WIDTH];
        12'hb86  : dbg_csr_rdata = mhpmcounter[3][2*DATA_WIDTH-1:DATA_WIDTH];
        12'hb87  : dbg_csr_rdata = mhpmcounter[4][2*DATA_WIDTH-1:DATA_WIDTH];
        12'hb88  : dbg_csr_rdata = mhpmcounter[5][2*DATA_WIDTH-1:DATA_WIDTH];
        12'hb89  : dbg_csr_rdata = mhpmcounter[6][2*DATA_WIDTH-1:DATA_WIDTH];
        12'hb8a  : dbg_csr_rdata = mhpmcounter[7][2*DATA_WIDTH-1:DATA_WIDTH];
        12'hb8b  : dbg_csr_rdata = mhpmcounter[8][2*DATA_WIDTH-1:DATA_WIDTH];
        12'hb8c  : dbg_csr_rdata = mhpmcounter[9][2*DATA_WIDTH-1:DATA_WIDTH];
        12'hb8d  : dbg_csr_rdata = mhpmcounter[10][2*DATA_WIDTH-1:DATA_WIDTH];
        12'hb8e  : dbg_csr_rdata = mhpmcounter[11][2*DATA_WIDTH-1:DATA_WIDTH];
        12'hb8f  : dbg_csr_rdata = mhpmcounter[12][2*DATA_WIDTH-1:DATA_WIDTH];
        12'hb90  : dbg_csr_rdata = mhpmcounter[13][2*DATA_WIDTH-1:DATA_WIDTH];
        12'hb91  : dbg_csr_rdata = mhpmcounter[14][2*DATA_WIDTH-1:DATA_WIDTH];
        12'hbc0  : dbg_csr_rdata = mcounterclr;
        12'hc01  : dbg_csr_rdata = mtime_shadow[DATA_WIDTH-1:0];
        12'hc81  : dbg_csr_rdata = mtime_shadow[2*DATA_WIDTH-1:DATA_WIDTH];
        default : dbg_csr_rdata = 'h0;
    endcase
end

`ifndef SYNTHESIS
// ==========================================================================
// SVA: 中断接受门控不变式（2026-09 中断边界语义修复的防线）
// 门控链一旦被改动破坏（如 EX_MEM 重定向拍门控被删），以下断言立即触发
// ==========================================================================
`ifndef FORMAL
// 1) EX_MEM 分支重定向拍禁止接受中断（branch_en_ex[1] 门控）
a_redirect_no_accept: assert property (
    @(posedge clk) disable iff (!rst_n)
    (branch_en_ex[1] |-> !int_trap_jump_n));
`else
// FORMAL 版：同契约 yosys 子集写法（时钟取外层 always、蕴含改 if 守卫）
fml_a_redirect_no_accept: assert property
    (branch_en_ex[1] ? !int_trap_jump_n : 1'b1);
`endif
// 2) Zcmp 多拍展开中禁止接受中断（int_come 门控含 ~zcmp_busy，此处防线冗余）
`ifdef FORMAL
fml_a_zcmp_no_accept: assert property
    (zcmp_busy ? !int_trap_jump_n : 1'b1);
`else
a_zcmp_no_accept: assert property (
    @(posedge clk) disable iff (!rst_n)
    (zcmp_busy |-> !int_trap_jump_n));
`endif
// 3) mret 屏蔽窗口内禁止接受中断（mret_gap_cnt + mret_req/done 门控）
`ifdef FORMAL
fml_a_mret_gap_no_accept: assert property
    ((mret_gap_cnt > 3'd0) ? !int_trap_jump_n : 1'b1);
`else
a_mret_gap_no_accept: assert property (
    @(posedge clk) disable iff (!rst_n)
    ((mret_gap_cnt > 3'd0) |-> !int_trap_jump_n));
`endif
// 4) 中断接受拍的 mepc 锁存源必须是合法指令地址（RVC 最低半字对齐）
`ifdef FORMAL
fml_a_accept_pc_aligned: assert property
    (int_trap_jump_n ? (id_ex_inst_addr[0] == 1'b0) : 1'b1);
`else
a_accept_pc_aligned: assert property (
    @(posedge clk) disable iff (!rst_n)
    (int_trap_jump_n |-> (id_ex_inst_addr[0] == 1'b0)));
`endif
// 5) 重定向拍 trap_jump 必须包含 int_trap_jump（防汇总式改动丢失中断分支）
`ifdef FORMAL
fml_a_int_trap_fire: assert property
    (int_trap_jump ? trap_jump : 1'b1);
`else
a_int_trap_fire: assert property (
    @(posedge clk) disable iff (!rst_n)
    (int_trap_jump |-> trap_jump));
`endif
// 6) 陷阱码哨兵：异常陷阱拍锁存的 mcause 不得携带全 1 哨兵（bit30=1）——
//    get_priority 优先级表缺项时 sel_stage 落 default，异常码 mux 输出全 1 且
//    mepc=0（2026-09-12 修复，mcause=0x7FFFFFFF 即此家族）
//    mret 拍 mcause_n 走默认 0 分支（无 trap 码语义），哨兵检查只针对
//    异常陷阱拍（exception_jump=1，mcause_n = {1'b0,exception_code}）
`ifdef FORMAL
// 哨兵契约（2026-09-12 mcause=0x7FFFFFFF 病根防线）：
// 异常触发拍（exception_trap=1）时，Pipeline_Ctrl 选中的阶段码
// exception_code 必为非哨兵（全 1 bit30=1 仅表示"无异常"）。
// 若 get_priority 优先级表缺项导致 sel_stage 落 default，
// 码 mux 输出全 1 哨兵 + mepc=0，mcause 锁存 0x7FFFFFFF。
// 直接引用输入端口（防 abc opt 消除内部 wire 后 witness 校验失败）
fml_a_exc_code_valid: assert property
    (exception_trap ? (exception_code != {DATA_WIDTH-2{1'b1}}) : 1'b1);
`else
property p_exc_code_valid;
    @(posedge clk) disable iff (!rst_n)
    (exception_trap |-> (exception_code != {DATA_WIDTH-2{1'b1}}));
endproperty
a_exc_code_valid: assert property (p_exc_code_valid)
    else $error("[SVA][CSR] 异常陷阱携带全1哨兵 exception_code=%h（核对 get_priority）", exception_code);
`endif
// 7) 中断原因编码合法：软件 3 / 定时 7 / 外部 11，且中断位（bit31）必须置位
`ifdef FORMAL
fml_a_int_code_legal: assert property
    (int_trap_jump_n
     ? (mcause_n[31] && (mcause_n[3:0] == 4'd3 || mcause_n[3:0] == 4'd7
                          || mcause_n[3:0] == 4'd11)) : 1'b1);
`else
property p_int_code_legal;
    @(posedge clk) disable iff (!rst_n)
    (int_trap_jump_n |-> (mcause_n[31] && (mcause_n[3:0] inside {4'd3, 4'd7, 4'd11})));
endproperty
a_int_code_legal: assert property (p_int_code_legal)
    else $error("[SVA][CSR] 中断原因码非法 mcause_n=%h", mcause_n);
`endif
// ===== FORMAL 覆盖点（SymbiYosys cover 任务）=====
// 注：cover 深度受限于中断接受门控链的时序约束——int_accept_kill 要求
// bus_ready=1 && oitf_stall=0 && 中断 pending 且使能（mstatus.MIE=1 需先
// 经 CSR 写入），30 步内路径过长；这些覆盖点由仿真（memstress 中断用例）
// 保证可达性，形式任务只证契约（prove）
`ifdef FORMAL
always @(posedge clk) begin
    fml_c_mret_gap_end:    cover property (mret_gap_cnt == 3'd0 && $past(mret_req));
    fml_c_zcmp_block_int:  cover property (zcmp_busy && int_trap);
end
`endif
`endif

endmodule
