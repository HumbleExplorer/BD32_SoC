`include "./../SoC_Config.sv"
`include "./../RV32_inst_Define.sv"
timeunit 1ns;
timeprecision 1ps;
module Mem_Access #(
    parameter ADDR_WIDTH = `ADDR_WIDTH,
    parameter DATA_WIDTH = `DATA_WIDTH,
    parameter ALIGN_WIDTH = `ALIGN_WIDTH,
    parameter ALIGN_BYTES = `ALIGN_BYTES,
    localparam BLOCK_SIZE_WIDTH = ADDR_WIDTH - `DEVICE_TAG_WIDTH,
    localparam APB_BASE_ADDR = `AXI_APB_BRIDGE_BASE
)(
    input   logic                       clk,
    input   logic                       rst_n,
    input   logic                       ex_mem_stall,
    input   logic                       ex_mem_flush,
    input   logic   [ADDR_WIDTH-1:0]    access_addr,
    input   logic                       access_en,
    input   logic                       access_wr,
    input   logic                       bus_tran_done,
    input   logic   [DATA_WIDTH-1:0]    dtcm_rdata,
    input   logic   [DATA_WIDTH-1:0]    itcm_rdata,
    input   logic   [DATA_WIDTH-1:0]    rd_bus_data,
    input   logic   [2:0]               access_func3,
    input   logic   [DATA_WIDTH-1:0]    access_wdata_raw, // rs2 原始 store 数据（未按地址移位）

    //to dtcm/bus
    output  logic                       dtcm_sel,
    output  logic                       bus_sel,
    output  logic                       apb_sel,        // APB 外设区域（非对齐访问不拆分，按规范抛异常）
    output  logic                       itcm_sel,       // CPU store 目标为 ITCM（自修改代码）
    output  logic                       itcm_load_sel,  // CPU load 目标为 ITCM（LSU 读指令区）
    // 非对齐拆分访问控制（拆成两次对齐访问）
    output  logic                       split_misaligned, // 当前 EX 级访问需要拆分（IDLE 检测拍有效）
    output  logic                       split_active,     // 拆分进行中（含最后合并拍）
    output  logic                       split_p2,         // 第二次访问拍（地址/写数据切换）
    output  logic                       split_xfer,       // P1/P2 访问执行拍（总线请求有效）
    output  logic                       split_xfer2,      // 第二访问值有效拍（P2 / 总线 P1 完成拍）
    output  logic                       split_xfer_off,   // 总线 P2 完成拍：撤销请求防多余事务
    output  logic   [ADDR_WIDTH-1:0]    split_base,       // 锁存的对齐基址（第一次访问目标）
    output  logic   [ADDR_WIDTH-1:0]    split_addr,       // 锁存基址 + 4（第二次访问目标）
    output  logic   [ADDR_WIDTH-1:0]    split_addr_use,   // 当前拍实际访问地址
    output  logic                       split_stall,      // 拆分期间流水线停顿
    output  logic                       split_wen_p1,     // 第一次 store 写使能（P1）
    output  logic                       split_wen,        // 第二次 store 写使能（P2）
    output  logic                       split_wr,         // 拆分目标为 store（总线方向）
    output  logic   [DATA_WIDTH-1:0]    split_wdata_p1,   // 第一次 store 数据
    output  logic   [ALIGN_BYTES-1:0]   split_wmask_p1,   // 第一次 store 字节使能
    output  logic   [DATA_WIDTH-1:0]    split_wdata,      // 第二次 store 数据
    output  logic   [ALIGN_BYTES-1:0]   split_wmask,      // 第二次 store 字节使能
    //to Mux (func3 expanded data, only for load instructions)
    output  logic   [DATA_WIDTH-1:0]    func3_expanded_data,
    // 锁存后的 load valid 信号，在 stall 周期保持数据选择正确
    output  logic                       tcm_rvalid,
    output  logic                       bus_rvalid
);

logic [DATA_WIDTH-1:0] access_rdata;
logic [DATA_WIDTH-1:0] tcm_rdata;

assign dtcm_sel     = access_en & (access_addr[ADDR_WIDTH-1:BLOCK_SIZE_WIDTH] == `DTCM_BASE_TAG) ;
assign bus_sel      = access_en & (access_addr[ADDR_WIDTH-1:BLOCK_SIZE_WIDTH] >= `BUS_BASE_ADDR) ;
assign apb_sel      = access_en & (access_addr[ADDR_WIDTH-1:BLOCK_SIZE_WIDTH] >= APB_BASE_ADDR[ADDR_WIDTH-1:BLOCK_SIZE_WIDTH]);
assign itcm_sel     = access_en & access_wr & (access_addr[ADDR_WIDTH-1:BLOCK_SIZE_WIDTH] == `ITCM_BASE_TAG);
assign itcm_load_sel = access_en & ~access_wr & (access_addr[ADDR_WIDTH-1:BLOCK_SIZE_WIDTH] == `ITCM_BASE_TAG);

// ============================================
// 非对齐访问拆分 FSM（DTCM / 总线内存）
// 一次非对齐访问拆成两次对齐访问：
//   IDLE：检测拍，锁存访问参数（地址/数据/宽度/读写方向）
//   P1：DTCM 第一次访问 / 总线第一次事务
//       - store/总线 load：访问对齐基址 base
//       - DTCM load：第一次读已在 IDLE 拍按原地址发起，本拍输出第二次读地址 base+4
//   P2：第二次访问（base+4，地址/写数据由本模块驱动）
//   P3：合并数据输出 + rvalid（仅 load）
// 总线访问的 P1/P2 各等待一次 bus_tran_done；DTCM 访问固定拍数。
// 注意 AXI 主机在 DONE 拍会组合式采样下一请求（take_req），因此：
//   - P1 的完成拍（bus_tran_done=1）必须已把第二访问的地址/数据摆在总线上；
//   - P2 的完成拍必须撤销 bus_transfer，防止主机锁存第三个（多余的）事务。
// ============================================
localparam SPLIT_IDLE = 3'd0;
localparam SPLIT_P1   = 3'd1;
localparam SPLIT_P2   = 3'd2;
localparam SPLIT_P3   = 3'd3;

logic [2:0]  split_state;
logic [2:0]  split_next;
logic        split_is_bus;       // 拆分目标为总线
logic        split_is_wr;        // 拆分目标为 store
logic [1:0]  split_off;          // 原地址低位偏移（字节）
logic [2:0]  split_func3;
logic [ADDR_WIDTH-1:0] split_base_q;   // 锁存的对齐基址
logic [DATA_WIDTH-1:0] split_wdata_raw_q; // 锁存的原始 store 数据
logic [DATA_WIDTH-1:0] split_word0;   // 第一次读回的 word（P2 拍锁存）
logic [DATA_WIDTH-1:0] split_word1;   // 第二次读回的 word（P3 拍锁存）
logic [DATA_WIDTH-1:0] split_merged;  // 合并后的完整访问数据
logic        split_rvalid;       // 拆分 load 的写回 valid（P3）

// 非对齐判定：
//   LH/LHU/SH（func3=001）：仅 addr[1:0]==2'b11 时跨字，需要拆分
//   LW/SW（func3=010）：addr[1:0]!=0 即跨字
//   LB/LBU/SB：恒对齐
// 拆分范围：DTCM + 总线内存（Flash/DDR）；APB 外设寄存器不拆分，
// 非对齐访问按规范抛 misaligned 异常（寄存器拆分会产生双重副作用）
always_comb begin
    split_misaligned = 1'b0;
    if (access_en && (dtcm_sel || (bus_sel && ~apb_sel))) begin
        case (access_func3)
            `INST_LH, `INST_LHU: split_misaligned = (access_addr[ALIGN_WIDTH-1:0] == {ALIGN_WIDTH{1'b1}});
            `INST_LW, `INST_SW:  split_misaligned = |access_addr[ALIGN_WIDTH-1:0];
            default:             split_misaligned = 1'b0;
        endcase
    end
end

always_comb begin
    split_next = split_state;
    case (split_state)
        SPLIT_IDLE: begin
            if (split_misaligned)
                split_next = SPLIT_P1;
        end
        SPLIT_P1: begin
            // 总线访问等第一次事务完成；DTCM 下一拍直接进入 P2
            if (~split_is_bus || bus_tran_done)
                split_next = SPLIT_P2;
        end
        SPLIT_P2: begin
            // 总线访问等第二次事务完成；DTCM 下一拍进入 P3（读数据返回）
            if (~split_is_bus || bus_tran_done)
                split_next = SPLIT_P3;
        end
        SPLIT_P3: begin
            split_next = SPLIT_IDLE;
        end
        default: split_next = SPLIT_IDLE;
    endcase
end

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        split_state  <= SPLIT_IDLE;
        split_is_bus <= 1'b0;
        split_is_wr  <= 1'b0;
        split_off    <= 2'd0;
        split_func3  <= 3'd0;
        split_base_q <= '0;
        split_wdata_raw_q <= '0;
        split_word0  <= '0;
        split_word1  <= '0;
    end else if (split_state == SPLIT_IDLE) begin
        if (split_misaligned) begin
            split_state  <= SPLIT_P1;
            split_is_bus <= bus_sel;
            split_is_wr  <= access_wr;
            split_off    <= access_addr[ALIGN_WIDTH-1:0];
            split_func3  <= access_func3;
            split_base_q <= {access_addr[ADDR_WIDTH-1:ALIGN_WIDTH], {ALIGN_WIDTH{1'b0}}};
            split_wdata_raw_q <= access_wdata_raw;
        end
        split_word0 <= '0;
        split_word1 <= '0;
    end else begin
        split_state <= split_next;
        // P1→P2：第一次读数据返回（DTCM 同步读；总线读数据在 P1 完成拍）
        if (split_state == SPLIT_P1) begin
            split_word0 <= split_is_bus ? rd_bus_data : dtcm_rdata;
        end
        // P2→P3：第二次读数据返回
        if (split_state == SPLIT_P2) begin
            split_word1 <= split_is_bus ? rd_bus_data : dtcm_rdata;
        end
    end
end

assign split_active     = (split_state != SPLIT_IDLE);
assign split_p2         = (split_state == SPLIT_P2);
assign split_xfer       = (split_state == SPLIT_P1) || (split_state == SPLIT_P2);
// 第二访问值有效拍：P2 全程；总线 P1 的完成拍（主机 DONE 拍会锁存下一请求）
assign split_xfer2      = (split_state == SPLIT_P2)
                        || (split_is_bus && (split_state == SPLIT_P1) && bus_tran_done);
// P2 完成拍：AXI 主机 DONE 拍会组合式采样下一请求，必须撤销 bus_transfer 防止锁存多余事务
assign split_xfer_off   = split_is_bus && (split_state == SPLIT_P2) && bus_tran_done;
assign split_stall      = split_active;
assign split_wen_p1     = (split_state == SPLIT_P1) && split_is_wr;
assign split_wen        = (split_state == SPLIT_P2) && split_is_wr;
assign split_wr         = split_is_wr & split_xfer;
assign split_rvalid     = (split_state == SPLIT_P3) && ~split_is_wr;
assign split_base       = split_base_q;
assign split_addr       = split_base_q + (ADDR_WIDTH'(1) << ALIGN_WIDTH);  // base + 4
// 当前拍实际访问地址：
//   DTCM load：P1 需输出第二次读地址（base+4，第一次读已在 IDLE 拍按原地址发起）
//   总线：P1 正常拍访问 base，P1 完成拍（DONE）即切换 base+4 供主机锁存
//   其余：P1 访问 base，P2 访问 base+4
assign split_addr_use   = ((split_state == SPLIT_P1) && ~split_is_wr && ~split_is_bus) ? split_addr
                        : split_xfer2 ? split_addr
                        : split_base;

// 拆分 store 的两次写数据/掩码：由锁存的原始数据推导，不依赖 Executer 的移位结果
always_comb begin
    split_wdata_p1 = '0;
    split_wmask_p1 = '0;
    split_wdata    = '0;
    split_wmask    = '0;
    if (split_is_wr) begin
        case (split_func3)
            `INST_SW: begin
                split_wmask_p1 = {ALIGN_BYTES{1'b1}} << split_off;
                split_wmask    = (32'd1 << split_off) - 32'd1;
                // word0 写 lanes off..3 / word1 写 lanes 0..off-1，按偏移显式拼接
                case (split_off)
                    2'd1: begin
                        split_wdata_p1 = {split_wdata_raw_q[23:0],  8'h0};
                        split_wdata    = {24'h0, split_wdata_raw_q[31:24]};
                    end
                    2'd2: begin
                        split_wdata_p1 = {split_wdata_raw_q[15:0], 16'h0};
                        split_wdata    = {16'h0, split_wdata_raw_q[31:16]};
                    end
                    default: begin  // off=3
                        split_wdata_p1 = {split_wdata_raw_q[7:0],  24'h0};
                        split_wdata    = { 8'h0, split_wdata_raw_q[31:8]};
                    end
                endcase
            end
            `INST_SH: begin
                // 半字仅在 off=3 拆分：word0 lane3 = raw[7:0]，word1 lane0 = raw[15:8]
                split_wdata_p1 = {split_wdata_raw_q[7:0], {DATA_WIDTH-8{1'b0}}};
                split_wmask_p1 = {1'b1, {(ALIGN_BYTES-1){1'b0}}};
                split_wdata    = {{DATA_WIDTH-8{1'b0}}, split_wdata_raw_q[15:8]};
                split_wmask    = {{(ALIGN_BYTES-1){1'b0}}, 1'b1};
            end
            default: ;
        endcase
    end
end

// 拆分 load 数据合并：word0 的高字节 + word1 的低字节
always_comb begin
    split_merged = '0;
    if (split_rvalid) begin
        case (split_func3)
            `INST_LH, `INST_LHU: begin
                // 半字仅 off=3 跨字：低字节 = word0[31:24]，高字节 = word1[7:0]
                split_merged[15:0] = {split_word1[7:0], split_word0[DATA_WIDTH-1 -: 8]};
            end
            `INST_LW: begin
                // 小端合并：addr 处字节为 word0 lane[off]，随地址递增逐 lane 上移，
                // 跨到 word1 的字节为结果高位
                case (split_off)
                    2'd1: split_merged = {split_word1[7:0],  split_word0[31:8]};
                    2'd2: split_merged = {split_word1[15:0], split_word0[31:16]};
                    2'd3: split_merged = {split_word1[23:0], split_word0[31:24]};
                    default: split_merged = split_word0;
                endcase
            end
            default: split_merged = split_word0;
        endcase
    end
end

// ============================================
// tcm_rvalid / bus_rvalid 锁存
// 在 stall 周期保持有效，确保数据选择和 func3 扩展正确
// ============================================
logic        tcm_rvalid_q;
logic        itcm_load_r;      // 上一拍 load 是否来自 ITCM（选择 tcm_rdata 数据源）
logic [2:0]  access_func3_r;
logic [1:0]  access_byte_r;
logic        stall_flsuh_r;

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        tcm_rvalid_q   <= #1 1'b0;
        itcm_load_r    <= #1 1'b0;
        access_func3_r <= #1 '0;
        access_byte_r  <= #1 '0;
        stall_flsuh_r  <= #1 1'b0;
    end else begin
        // stall/flush 期间禁止更新：此时 access_addr/access_func3 来自 EX 级
        // 的不同指令（ex_mem 未 stall/flush 时 EX 级仍在前进），
        // 锁存 rvalid 会导致"用旧 rvalid 选新地址数据"的不一致。
        // 只有在 ex_mem_stall=0 && ex_mem_flush=0 时才更新，保证 rvalid 和 func3 与
        // 对应指令的 load 地址严格同步。
        stall_flsuh_r <= #1 ex_mem_stall | ex_mem_flush;
        // 拆分进行中强制清 stall 延迟：否则拆分结束（P3→IDLE）后第一个非拆分 load
        // 的首拍会被残留的 stall_flsuh_r 盖住，rvalid 捕获被跳过导致读数据丢失
        if (split_active)
            stall_flsuh_r <= #1 1'b0;
        // 拆分检测拍（IDLE）不清除旧的 rvalid 会污染下一次写回：
        // 拆分 load 的写回由 split_rvalid 在 P3 单独给出，检测拍与拆分进行中均强制清 rvalid
        if (~stall_flsuh_r && ~split_active && ~split_misaligned) begin
            tcm_rvalid_q   <= #1 (~access_wr && (dtcm_sel || itcm_load_sel));
            // CORE_TEST 下 ITCM/DTCM 共享窗口（tag 相同）：load 数据取 DTCM（镜像），不取 ITCM 读口
            itcm_load_r    <= #1 (~access_wr && itcm_load_sel && ~dtcm_sel);
            if (~access_wr && (dtcm_sel || itcm_load_sel || bus_sel)) begin
                access_func3_r <= #1 access_func3;
                access_byte_r  <= #1 access_addr[1:0];
            end
        end
        // 拆分访问期间强制清 rvalid：rvalid 由 FSM 在最后合并拍给出
        if (split_active || split_misaligned) begin
            tcm_rvalid_q <= #1 1'b0;
        end
        // stall/flush 期间不清零 rvalid（保持旧值，等 stall 解除后再
        // 被新的 load/store 覆盖），确保 DTCM 同步读 1 拍延迟的数据不被丢弃
        // 即保持rvalid至读出数据
    end
end

assign tcm_rvalid = tcm_rvalid_q | split_rvalid;
assign bus_rvalid  = (~access_wr && bus_tran_done && ~split_active) | split_rvalid;
// TCM 读数据：ITCM load 取 ITCM 读口输出，否则取 DTCM
assign tcm_rdata   = itcm_load_r ? itcm_rdata : dtcm_rdata;

// 读数据选择：使用锁存后的 valid 信号，在 stall 周期仍能正确选择数据源
assign access_rdata = split_rvalid        ? split_merged :
                      tcm_rvalid          ? tcm_rdata   :
                      bus_rvalid          ? rd_bus_data : '0;

// 符号扩展：使用锁存后的 func3 和地址低位，在 stall 周期保持正确
always_comb begin
    if (tcm_rvalid | bus_rvalid) begin
        case (split_rvalid ? split_func3 : access_func3_r)
            `INST_LB : begin
                case (split_rvalid ? split_off : access_byte_r)
                    2'b00:func3_expanded_data = {{24{access_rdata[7]}},access_rdata[7:0]};
                    2'b01:func3_expanded_data = {{24{access_rdata[15]}},access_rdata[15:8]};
                    2'b10:func3_expanded_data = {{24{access_rdata[23]}},access_rdata[23:16]};
                    2'b11:func3_expanded_data = {{24{access_rdata[31]}},access_rdata[31:24]};
                    default:func3_expanded_data = {{24{access_rdata[7]}},access_rdata[7:0]};
                endcase
            end
            `INST_LH : begin
                if (split_rvalid) begin
                    // 拆分结果已合并到 [15:0]，直接取低半字
                    func3_expanded_data = {{16{access_rdata[15]}},access_rdata[15:0]};
                end else begin
                    case (access_byte_r)
                        2'b00:func3_expanded_data = {{16{access_rdata[15]}},access_rdata[15:0]};
                        2'b01:func3_expanded_data = {{16{access_rdata[23]}},access_rdata[23:8]};
                        2'b10:func3_expanded_data = {{16{access_rdata[31]}},access_rdata[31:16]};
                        default:func3_expanded_data = {{16{access_rdata[15]}},access_rdata[15:0]};
                    endcase
                end
            end
            `INST_LW : begin
                func3_expanded_data = access_rdata;
            end
            `INST_LBU : begin
                case (split_rvalid ? split_off : access_byte_r)
                    2'b00:func3_expanded_data = {24'h0,access_rdata[7:0]};
                    2'b01:func3_expanded_data = {24'h0,access_rdata[15:8]};
                    2'b10:func3_expanded_data = {24'h0,access_rdata[23:16]};
                    2'b11:func3_expanded_data = {24'h0,access_rdata[31:24]};
                    default:func3_expanded_data = {24'h0,access_rdata[7:0]};
                endcase
            end
            `INST_LHU : begin
                if (split_rvalid) begin
                    func3_expanded_data = {16'h0,access_rdata[15:0]};
                end else begin
                    case (access_byte_r)
                        2'b00:func3_expanded_data = {16'h0,access_rdata[15:0]};
                        2'b01:func3_expanded_data = {16'h0,access_rdata[23:8]};
                        2'b10:func3_expanded_data = {16'h0,access_rdata[31:16]};
                        default:func3_expanded_data = {16'h0,access_rdata[15:0]};
                    endcase
                end
            end
            default : func3_expanded_data = '0;
        endcase
    end else begin
        func3_expanded_data = '0;
    end
end


endmodule
