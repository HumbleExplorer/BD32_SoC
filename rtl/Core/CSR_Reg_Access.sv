`include "./../SoC_Config.sv"
`include "./../RV32_inst_Define.sv"
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
    output  logic                           trap_jump,
    output  logic   [DATA_WIDTH-1:0]        trap_jump_addr
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
logic   trap_occur;
logic   trap_return;
logic   [DATA_WIDTH-1:0] mcause_temp;

logic           int_come;
logic           waiting_int;

// 优先级：外部中断>软件中断>定时器中断
assign external_int_trap = mstatus[3] & mip[11] & mie[11];
assign software_int_trap = mstatus[3] & mip[3] & mie[3] & (!external_int_trap);
assign timer_int_trap    = mstatus[3] & mip[7] & mie[7] & (!external_int_trap & !software_int_trap);
assign int_trap     = external_int_trap | software_int_trap | timer_int_trap;
assign int_come     = (mip[11] & mie[11]) | (mip[3] & mie[3]) | (mip[7] & mie[7]);
assign waiting_int  = (!int_come & wfi_req);

assign priv_mode = mstatus[12:11];
assign trap_occur = exception_trap | int_trap;
assign trap_return = mret_req;
assign trap_jump = trap_occur | trap_return;

always_comb begin 
    if (exception_trap) mcause_temp = {1'b0,exception_code};
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
    if(exception_trap)
        trap_jump_addr = {mtvec[31:2],2'b00};
    else if (mret_req)
        trap_jump_addr = mepc;
    else if (int_trap)
        trap_jump_addr = mtvec[0] ? ({mtvec[31:2] + mcause_temp[30:0] ,2'b00}): {mtvec[31:2],2'b00};
    else
        trap_jump_addr = 'h0;
end

always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        mstatus             <= 'h00001800;
        mie                 <= 'h0;
        mtvec               <= 'h0;
        mepc                <= 'h0;
        mcause              <= 'h0;
        mtval               <= 'h0;
        mcounteren          <= 'h0;
        mcountinhibit       <= 'h0;
        mip                 <= 'h0;
        mcycle_clear        <= 'h0;
        minstret_clear      <= 'h0;
    end else begin//优先级：异常>外部中断>软件中断>定时器中断
        mip <= {mip[31:12],external_int,mip[10:8],timer_int,mip[6:4],software_int,mip[2:0]};
        mcause <= mcause_temp;//写入异常原因 
        if (exception_trap) begin//进入异常
            mstatus[7] <= mstatus[3];//MPIE <- MIE
            mstatus[3] <= 1'b0;//禁用全局中断
            mepc <= exception_inst_addr;//保存异常PC值
            mtval <= exception_val;//保存异常信息
        end else if (mret_req) begin//从异常返回
            mepc <= 'd0;
            mstatus[3] <= mstatus[7];//MIE <- MPIE
            mstatus[7] <= 1'b1;
        end else if(int_trap) begin
            mepc <= next_inst_addr;
            mstatus[7] <= mstatus[3];
            mstatus[3] <= 1'b0;//禁用全局中断，如果需要嵌套中断需要通过软件设置mstatus
        end else if(access_csr_en) begin
            case(csr_addr)
                12'h300  : mstatus          <= {mstatus[31:8],wr_csr_data[7],mstatus[6:4],wr_csr_data[3],mstatus[2:0]};//特权模式保持M模式，写MIE和MPIE
                12'h304  : mie              <= {mie[31:12],wr_csr_data[11],mie[10:8],wr_csr_data[7],mie[6:4],wr_csr_data[3],mie[2:0]};
                12'h305  : mtvec            <= wr_csr_data;
                12'h306  : mcounteren       <= wr_csr_data;
                12'h320  : mcountinhibit    <= wr_csr_data;
                12'h341  : mepc             <= wr_csr_data;
                // 12'h342  : mcause           <= wr_csr_data;
                // 12'h343  : mtval            <= wr_csr_data;
                // 12'h344  : mip              <= wr_csr_data;
                //自定义寄存器
                12'hbc4  : begin

                end
                12'hbc5  : begin
                    mcycle_clear            <= wr_csr_data[0];
                    minstret_clear          <= wr_csr_data[2];
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
            12'hb00  : rd_csr_data = mcounteren[0] ? mcycle[DATA_WIDTH-1:0] : 'h0;
            12'hb80  : rd_csr_data = mcounteren[0] ? mcycle[2*DATA_WIDTH-1:DATA_WIDTH] : 'h0;
            12'hb02  : rd_csr_data = mcounteren[2] ? minstret[DATA_WIDTH-1:0] : 'h0;
            12'hb82  : rd_csr_data = mcounteren[2] ? minstret[2*DATA_WIDTH-1:DATA_WIDTH] : 'h0;
            default  : begin
                illegal_inst_csr = 1'b1;
            end
        endcase
    end
end


always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        mcycle <= 'h0;
    else if(mcycle_clear)
        mcycle <= 'h0;
    else if(mcountinhibit[0])
        mcycle <= mcycle;
    else
        mcycle <= mcycle + 'h1;
end

always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        minstret <= 'h0; 
    else if(minstret_clear) 
        minstret <= 'h0;
    else if(mcountinhibit[2])
        minstret <= minstret;
    else
        minstret <= minstret + 'h1;
end


endmodule