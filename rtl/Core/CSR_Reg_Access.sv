`include "./../SoC_Config.sv"
`include "./../RV32_inst_Define.sv"
`timescale 1ns / 1ps
module CSR_Reg_Access #(
    parameter ADDR_WIDTH = `ADDR_WIDTH,
    parameter DATA_WIDTH = `DATA_WIDTH,
    parameter CSR_ADDR_WIDTH = `CSR_ADDR_WIDTH
)(
    input   logic                           clk,
    input   logic                           rst_n,
    input   logic                           access_csr_en,
    input   logic   [CSR_ADDR_WIDTH-1:0]    csr_addr,
    input   logic   [DATA_WIDTH-1:0]        wr_csr_data,
    output  logic   [DATA_WIDTH-1:0]        rd_csr_data,
// from ctrl
    input   logic   [ADDR_WIDTH-1:0]        exception_inst_addr,
    input   logic   [ADDR_WIDTH-1:0]        next_inst_addr,//IF/ID或者jump_addr
    input   logic                           bus_access_ready,
    input   logic                           mul_div_ready,
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
// to CLINT
);

//机器陷阱配置
logic   [DATA_WIDTH-1:0]    mstatus;//状态0x300
logic   [DATA_WIDTH-1:0]    mie;//中断使能0x304
logic   [DATA_WIDTH-1:0]    mtvec;//中断向量（异常处理程序基地址）0x305
logic   [DATA_WIDTH-1:0]    mcounteren;
logic   [DATA_WIDTH-1:0]    mcountinhibit;
//机器陷阱处理程序
logic   [DATA_WIDTH-1:0]    mepc;//异常PC
logic   [DATA_WIDTH-1:0]    mcause;//异常原因
logic   [DATA_WIDTH-1:0]    mtval;//错误地址或命令
logic   [DATA_WIDTH-1:0]    mip;//中断挂起

//机器计数器/计时器
logic   [2*DATA_WIDTH-1:0]  mcycle;
logic   [2*DATA_WIDTH-1:0]  minstret;
logic                       mcycle_clear;
logic                       minstret_clear;

logic   external_int_trap, software_int_trap, timer_int_trap;
logic   [DATA_WIDTH-1:0] mcause_temp;
logic   [DATA_WIDTH-1:0] int_jump_addr;
logic                    int_trap_latched;   // 中断延迟1拍：本周期预算地址，下周期触发
logic           int_come;
logic           exception_jump;
logic           int_waiting_jump;
logic           int_trap_jump;

// 优先级：外部中断>软件中断>定时器中断
assign external_int_trap = mstatus[3] & mip[11] & mie[11];
assign software_int_trap = mstatus[3] & mip[3] & mie[3] & (!external_int_trap);
assign timer_int_trap    = mstatus[3] & mip[7] & mie[7] & (!external_int_trap & !software_int_trap);
assign int_trap     = external_int_trap | software_int_trap | timer_int_trap;
assign int_come     = (mip[11] & mie[11]) | (mip[3] & mie[3]) | (mip[7] & mie[7]);


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
        mcause_temp = {1'b0,exception_code};
    else if (external_int_trap)
        mcause_temp = {1'd1,31'd11};
    else if (software_int_trap)
        mcause_temp = {1'd1,31'd3};
    else if (timer_int_trap)
        mcause_temp = {1'd1,31'd7};
    else
        mcause_temp = 'h0;
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

// 中断预计算：int_trap 有效且无异常时，锁存 trap 地址（CARRY4 不参与关键路径）
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        int_waiting_jump <= #1 1'b0;
        int_jump_addr    <= #1 'h0;
        int_trap_jump    <= #1 1'b0;
    end else begin
        int_waiting_jump <= #1 int_trap ? 1'b1 :
                                (bus_access_ready & mul_div_ready) ? 1'b0 :
                                int_waiting_jump;
        int_trap_jump   <= #1 (int_waiting_jump | int_trap) && (bus_access_ready & mul_div_ready);
        int_jump_addr   <= #1 int_trap ?(mtvec[0]                         // 本周期预计算，下周期直接用
                        ? ({mtvec[31:2] + mcause_temp[3:0], 2'b00}) : {mtvec[31:2], 2'b00}) : int_jump_addr;
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
        mip                 <= #1 'h0;
        mcycle_clear        <= #1 'h0;
        minstret_clear      <= #1 'h0;
    end else begin//优先级：异常>外部中断>软件中断>定时器中断
        mip     <= #1 {mip[31:12],external_int,mip[10:8],timer_int,mip[6:4],software_int,mip[2:0]};
        mcause  <= #1 mcause_temp;//写入异常原因
        if (exception_trap) begin//进入异常
            mstatus[7]  <= #1 mstatus[3];//MPIE <- MIE
            mstatus[3]  <= #1 1'b0;//禁用全局中断
            mepc        <= #1 exception_inst_addr;//保存异常PC值
            mtval       <= #1 exception_val;//保存异常信息
        end else if (mret_req) begin//从异常返回 mepc保持不变
            mstatus[3]  <= #1 mstatus[7];//MIE <- MPIE
            mstatus[7]  <= #1 1'b1;
        end else if(int_trap && !wfi_req) begin
            mepc        <= #1 next_inst_addr;
            mstatus[7]  <= #1 mstatus[3];
            mstatus[3]  <= #1 1'b0;//禁用全局中断，如果需要嵌套中断需要通过软件设置mstatus
        end else if(access_csr_en) begin
            case(csr_addr)
                12'h300  : mstatus          <= #1 {mstatus[31:8],wr_csr_data[7],mstatus[6:4],wr_csr_data[3],mstatus[2:0]};//特权模式保持M模式，写MIE和MPIE
                12'h304  : mie              <= #1 {mie[31:12],wr_csr_data[11],mie[10:8],wr_csr_data[7],mie[6:4],wr_csr_data[3],mie[2:0]};
                12'h305  : mtvec            <= #1 wr_csr_data;
                12'h306  : mcounteren       <= #1 wr_csr_data;
                12'h320  : mcountinhibit    <= #1 wr_csr_data;
                12'h341  : mepc             <= #1 wr_csr_data;
                // 12'h342  : mcause           <= #1 wr_csr_data;
                // 12'h343  : mtval            <= #1 wr_csr_data;
                // 12'h344  : mip              <= #1 wr_csr_data;
                //自定义寄存器
                12'hbc4  : begin

                end
                12'hbc5  : begin
                    mcycle_clear            <= #1 wr_csr_data[0];
                    minstret_clear          <= #1 wr_csr_data[2];
                end
                default  : ;
            endcase
        end
    end
end

always_comb begin
    rd_csr_data = 'h0;
    illegal_inst_csr = 1'b0;
    if (access_csr_en) begin
        case(csr_addr)
            12'h300  : rd_csr_data = mstatus;
            12'h304  : rd_csr_data = mie;
            12'h305  : rd_csr_data = mtvec;
            12'h306  : rd_csr_data = mcounteren;
            12'h320  : rd_csr_data = mcountinhibit;
            12'h341  : rd_csr_data = mepc;
            12'h342  : rd_csr_data = mcause;
            12'h343  : rd_csr_data = mtval;
            12'h344  : rd_csr_data = mip;
            12'hb00  : rd_csr_data = mcycle[DATA_WIDTH-1:0];
            12'hb80  : rd_csr_data = mcycle[2*DATA_WIDTH-1:DATA_WIDTH];
            12'hb02  : rd_csr_data = minstret[DATA_WIDTH-1:0];
            12'hb82  : rd_csr_data = minstret[2*DATA_WIDTH-1:DATA_WIDTH];
            default  : begin
                illegal_inst_csr = 1'b1;
            end
        endcase
    end
end


always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        mcycle <= #1 'h0;
    else if(mcycle_clear)
        mcycle <= #1 'h0;
    else if(mcountinhibit[0])
        mcycle <= #1 mcycle;
    else
        mcycle <= #1 mcycle + 'h1;
end

always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        minstret <= #1 'h0; 
    else if(minstret_clear) 
        minstret <= #1 'h0;
    else if(mcountinhibit[2])
        minstret <= #1 minstret;
    else
        minstret <= #1 minstret + 'h1;
end

endmodule