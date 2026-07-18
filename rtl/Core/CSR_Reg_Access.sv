`include "./../SoC_Config.sv"
`include "./../RV32_inst_Define.sv"
timeunit 1ns;
timeprecision 1ps;
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
    input   logic   [2*DATA_WIDTH-1:0]      mtime_shadow,// 只读影子
// to EX
    output  logic                           illegal_inst_csr,
// to ctrl
    output  logic   [1:0]                   priv_mode,//特权模式 0：U；  1：S；  3：M
    (* MAX_FANOUT = 16 *)output  logic                           trap_jump,
    output  logic   [DATA_WIDTH-1:0]        trap_jump_addr,
    output  logic                           waiting_int
`ifdef ENABLE_HPM
    ,
    input   logic                           hpm_valid,
    input   logic   [2:0]                   hpm_inst_type,
    input   logic                           hpm_mispredict
`endif
// to CLINT
);

//机器陷阱配置
logic   [DATA_WIDTH-1:0]    mstatus;//状态0x300
logic   [DATA_WIDTH-1:0]    mie;//中断使能0x304
logic   [DATA_WIDTH-1:0]    mtvec;//中断向量（异常处理程序基地址）0x305

//机器陷阱处理程序
logic   [DATA_WIDTH-1:0]    mepc;//异常PC
logic   [DATA_WIDTH-1:0]    mcause;//异常原因
logic   [DATA_WIDTH-1:0]    mtval;//错误地址或命令
logic   [DATA_WIDTH-1:0]    mip;//中断挂起

//机器计数器/计时器
logic   [2*DATA_WIDTH-1:0]  mcycle;
logic   [2*DATA_WIDTH-1:0]  minstret;
logic   [DATA_WIDTH-1:0]    mcounteren;
logic   [DATA_WIDTH-1:0]    mcountinhibit;
logic   [DATA_WIDTH-1:0]    mcounterclr;

always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        mcycle <= #1 'h0;
    else if(mcounterclr[0])
        mcycle <= #1 'h0;
    else if(mcountinhibit[0])
        mcycle <= #1 mcycle;
    else if (mcounteren[0])
        mcycle <= #1 mcycle + 'h1;
end

always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        minstret <= #1 'h0; 
    else if(mcounterclr[2]) 
        minstret <= #1 'h0;
    else if(mcountinhibit[2])
        minstret <= #1 minstret;
    else if (hpm_valid && mcounteren[2])
        minstret <= #1 minstret + 'h1;
end

`ifdef ENABLE_HPM
// HPM 计数器（64位，0xBC3-0xBC9/0xC43-0xC49）
// 各计数器受 mcounteren / mcountinhibit / mcounterclr 对应位控制
//   mhp_counter3 (ALU)      0
//   mhp_counter4 (LOAD)     1
//   mhp_counter5 (STORE)    2
//   mhp_counter6 (BRANCH)   3
//   mhp_counter7 (JUMP)     4
//   mhp_counter8 (MULDIV)   5
//   mhp_counter9 (MISPREDICT) 6
// WB 级指令类型: 0:OTHER 1:ALU 2:LOAD 3:STORE 4:BRANCH 5:JUMP 6:MULDIV
logic   [2*DATA_WIDTH-1:0]  mhpmcounter[7];

generate
    genvar i;
    for (i = 0; i < 6; i = i + 1) begin
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
            else if (hpm_valid && mcounteren[i+3] && hpm_inst_type == i+1) begin
                mhpmcounter[i] <= #1 mhpmcounter[i] + 'h1;
            end
        end
    end
endgenerate


// 预测成功计数器（mhp_counter9, bit 9）
always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n)                              mhpmcounter[6] <= #1 'h0;
    else if(mcounterclr[9])                 mhpmcounter[6] <= #1 'h0;
    else if(mcountinhibit[9])               mhpmcounter[6] <= #1 mhpmcounter[6];
    else if(hpm_valid && mcounteren[9] && (hpm_inst_type == 3'd4 || hpm_inst_type == 3'd5) && hpm_mispredict)
                                            mhpmcounter[6] <= #1 mhpmcounter[6] + 'h1;
end

`endif

logic   int_trap;
logic   external_int_trap, software_int_trap, timer_int_trap;
logic   [DATA_WIDTH-1:0] mcause_n;
logic   [DATA_WIDTH-1:0] int_jump_addr;
logic                    int_come;
logic                    exception_jump;
logic                    int_waiting_jump;
logic                    int_trap_jump;

// 优先级：外部中断>软件中断>定时器中断
assign external_int_trap = mstatus[3] & mip[11] & mie[11];
assign software_int_trap = mstatus[3] & mip[3] & mie[3] & (!external_int_trap);
assign timer_int_trap    = mstatus[3] & mip[7] & mie[7] & (!external_int_trap & !software_int_trap);
assign int_come     = (mip[11] & mie[11]) | (mip[3] & mie[3]) | (mip[7] & mie[7]);
assign int_trap     = mstatus[3] & int_come;

assign priv_mode = mstatus[12:11];
assign exception_jump = exception_trap;
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
assign int_trap_jump_n = (int_waiting_jump | int_trap) && (bus_ready && ~oitf_stall) && ~int_trap_jump;
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
        mcounteren          <= #1 'h0;
        mcountinhibit       <= #1 'h0;
        mcounterclr         <= #1 'h0;
        mip                 <= #1 'h0;
    end else begin//优先级：异常>外部中断>软件中断>定时器中断
        mip     <= #1 {mip[31:12],external_int,mip[10:8],timer_int,mip[6:4],software_int,mip[2:0]};
        mcause  <= #1 mcause_n;//写入异常原因
        if (exception_trap) begin//进入异常
            mstatus[7]  <= #1 mstatus[3];//MPIE <- MIE
            mstatus[3]  <= #1 1'b0;//禁用全局中断
            mepc        <= #1 exception_inst_addr;//保存异常PC值
            mtval       <= #1 exception_val;//保存异常信息
        end else if (mret_req) begin//从异常返回 mepc保持不变
            mstatus[3]  <= #1 mstatus[7];//MIE <- MPIE
            mstatus[7]  <= #1 1'b1;
        end else if(int_trap_jump_n) begin//int_trap_jump前一周期判断，防止长周期指令和跳转指令间的相关性导致next_inst_addr错误
            mepc        <= #1 next_inst_addr;
            mstatus[7]  <= #1 mstatus[3];
            mstatus[3]  <= #1 1'b0;//禁用全局中断，如果需要嵌套中断需要通过软件设置mstatus
        end else if(csr_en) begin
            case(csr_addr)
                12'h300  : mstatus          <= #1 {mstatus[31:8],csr_wdata[7],mstatus[6:4],csr_wdata[3],mstatus[2:0]};//特权模式保持M模式，写MIE和MPIE
                12'h304  : mie              <= #1 {mie[31:12],csr_wdata[11],mie[10:8],csr_wdata[7],mie[6:4],csr_wdata[3],mie[2:0]};
                12'h305  : mtvec            <= #1 csr_wdata;
                12'h306  : mcounteren       <= #1 csr_wdata;
                12'h320  : mcountinhibit    <= #1 csr_wdata;
                12'h341  : mepc             <= #1 csr_wdata;
                // 12'h342  : mcause           <= #1 csr_wdata;
                // 12'h343  : mtval            <= #1 csr_wdata;
                // 12'h344  : mip              <= #1 csr_wdata;
                //自定义寄存器
                12'hbc0  : begin
                    mcounterclr <= #1 csr_wdata;
                end
                default  : ;
            endcase
        end
    end
end

always_comb begin
    csr_rdata = 'h0;
    illegal_inst_csr = 1'b0;
    if (csr_en) begin
        case(csr_addr)
            12'h300  : csr_rdata = mstatus;
            12'h304  : csr_rdata = mie;
            12'h305  : csr_rdata = mtvec;
            12'h306  : csr_rdata = mcounteren;
            12'h320  : csr_rdata = mcountinhibit;
            12'h341  : csr_rdata = mepc;
            12'h342  : csr_rdata = mcause;
            12'h343  : csr_rdata = mtval;
            12'h344  : csr_rdata = mip;
            12'hb00  : csr_rdata = mcycle[DATA_WIDTH-1:0];
            12'hb80  : csr_rdata = mcycle[2*DATA_WIDTH-1:DATA_WIDTH];
            12'hb02  : csr_rdata = minstret[DATA_WIDTH-1:0];
            12'hb82  : csr_rdata = minstret[2*DATA_WIDTH-1:DATA_WIDTH];
`ifdef ENABLE_HPM
            // hpm_counter3-9 / 3h-9h (CSR 0xBC3-0xBC9 / 0xC43-0xC49)
            12'hbc3  : csr_rdata = mhpmcounter[0][DATA_WIDTH-1:0];  // ALU
            12'hbc4  : csr_rdata = mhpmcounter[1][DATA_WIDTH-1:0];  // LOAD
            12'hbc5  : csr_rdata = mhpmcounter[2][DATA_WIDTH-1:0];  // STORE
            12'hbc6  : csr_rdata = mhpmcounter[3][DATA_WIDTH-1:0];  // BRANCH
            12'hbc7  : csr_rdata = mhpmcounter[4][DATA_WIDTH-1:0];  // JUMP
            12'hbc8  : csr_rdata = mhpmcounter[5][DATA_WIDTH-1:0];  // MULDIV
            12'hbc9  : csr_rdata = mhpmcounter[6][DATA_WIDTH-1:0];  // 预测成功
            // hpm_counter3h-9h (高32位)
            12'hc43  : csr_rdata = mhpmcounter[0][2*DATA_WIDTH-1:DATA_WIDTH];
            12'hc44  : csr_rdata = mhpmcounter[1][2*DATA_WIDTH-1:DATA_WIDTH];
            12'hc45  : csr_rdata = mhpmcounter[2][2*DATA_WIDTH-1:DATA_WIDTH];
            12'hc46  : csr_rdata = mhpmcounter[3][2*DATA_WIDTH-1:DATA_WIDTH];
            12'hc47  : csr_rdata = mhpmcounter[4][2*DATA_WIDTH-1:DATA_WIDTH];
            12'hc48  : csr_rdata = mhpmcounter[5][2*DATA_WIDTH-1:DATA_WIDTH];
            12'hc49  : csr_rdata = mhpmcounter[6][2*DATA_WIDTH-1:DATA_WIDTH];
`endif
            // time / timeh — 只读影子寄存器（mtime_shadow 来自 CLINT）
            12'hc01  : csr_rdata = mtime_shadow[DATA_WIDTH-1:0];          // time (低32位)
            12'hc81  : csr_rdata = mtime_shadow[2*DATA_WIDTH-1:DATA_WIDTH]; // timeh (高32位)
            default  : begin
                illegal_inst_csr = 1'b1;
            end
        endcase
    end
end

endmodule