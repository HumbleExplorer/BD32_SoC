`include "./../SoC_Config.sv"
`include "./../RV32_inst_Define.sv"
timeunit 1ns;
timeprecision 1ps;
// =============================================================================
// RVC_Expander — RV32C 压缩指令 -> RV32I 等价指令（纯组合展开）
// -----------------------------------------------------------------------------
// 支持完整 RV32IMC 压缩指令集 + Zcb 子扩展（无 F/D、无 RV64 指令、无 Zcmp/Zcmt；
// Zcb 的 c.zext.h/c.sext.b/c.sext.h 展开目标为 Zbb 指令，需 Zbb 已实现）。
// 保留编码输出 illegal_o=1；HINT 编码（rd=x0 等）统一展开为 NOP（INST_NOP）。
// 编码位域与 RISC-V Unprivileged Spec / Ibex ibex_compressed_decoder 对照。
// 关键点：
//   - C.JAL 仅在 RV32 存在（此处按 RV32 实现）；
//   - C.SLLI/C.SRLI/C.SRAI 在 RV32 下 shamt[5] 必须为 0，否则保留；
//   - 链接地址语义（C.JAL/C.JALR 的 pc+2）由流水线 is_compressed 标志处理，
//     本模块只负责指令编码展开。
// =============================================================================
module RVC_Expander (
    input  logic [15:0] rvc_inst,   // 16 位压缩指令（低 16 位）
    output logic [31:0] inst_o,     // 展开后的 32 位指令
    output logic        illegal_o,  // 保留编码（保留指令异常）
    output logic        zcmp_en_o,  // Zcmp 指令（由 Zcmp_Expander FSM 展开）
    output logic        zcb_en_o    // Zcb 指令（HPM 扩展计数用）
);

  logic [2:0]  funct3;
  logic [3:0]  funct4;
  logic [2:0]  funct2;
  logic [4:0]  rs1, rs2, rd, shamt;
  logic [2:0]  rs1_c, rs2_c, rd_c;

  assign funct3 = rvc_inst[15:13];
  assign funct4 = rvc_inst[15:12];
  assign funct2 = rvc_inst[6:5];
  assign rs1    = rvc_inst[11:7];
  assign rs2    = rvc_inst[6:2];
  assign rd     = rvc_inst[11:7];
  assign shamt  = rvc_inst[6:2];
  assign rs1_c  = rvc_inst[9:7];
  assign rs2_c  = rvc_inst[4:2];
  assign rd_c   = rvc_inst[4:2];

  always_comb begin
    inst_o    = {16'b0, rvc_inst};          // 默认：原样（非法路径兜底）
    illegal_o = 1'b0;
    zcmp_en_o = 1'b0;
    zcb_en_o  = 1'b0;

    unique case (rvc_inst[1:0])
      // ================= 象限 0（CIW/CL/CSS）=================
      2'b00: begin
        unique case (funct3)
          3'b000: begin
            // C.ADDI4SPN -> addi rd', x2, nzuimm[9:2]（nzuimm=0 保留）
            inst_o = {2'b0, rvc_inst[10:7], rvc_inst[12:11], rvc_inst[5],
                      rvc_inst[6], 2'b00, 5'h02, 3'b000, 2'b01, rd_c, 7'b0010011};
            if (rvc_inst[12:5] == 8'b0) illegal_o = 1'b1;
          end
          3'b010: begin
            // C.LW -> lw rd', imm(rs1')：uimm={i5,i12:10,i6}
            inst_o = {5'b0, rvc_inst[5], rvc_inst[12:10], rvc_inst[6],
                      2'b00, 2'b01, rs1_c, 3'b010, 2'b01, rd_c, 7'b0000011};
          end
          3'b110: begin
            // C.SW -> sw rs2', imm(rs1')
            inst_o = {5'b0, rvc_inst[5], rvc_inst[12], 2'b01, rs2_c,
                      2'b01, rs1_c, 3'b010, rvc_inst[11:10], rvc_inst[6],
                      2'b00, 7'b0100011};
          end
          3'b100: begin
            // Zcb 压缩字节/半字 load/store（C0 象限 [15:13]=100）。
            // 立即数位域：uimm[1:0] = {inst[5], inst[6]}；半字指令 uimm[0] 恒 0，
            //   且 inst[6] 有语义（lhu/lh 之分，sh 的 inst[6]=1 为保留）。
            unique case (rvc_inst[12:10])
              3'b000: begin
                // C.LBU -> lbu rd', uimm(rs1')（funct3=100，零扩展）
                inst_o = {10'b0, rvc_inst[5], rvc_inst[6], 2'b01, rs1_c,
                          3'b100, 2'b01, rd_c, 7'b0000011};
                zcb_en_o = 1'b1;
              end
              3'b001: begin
                if (rvc_inst[6] == 1'b0) begin
                  // C.LHU -> lhu rd', uimm(rs1')（funct3=101，uimm={inst[5],0}）
                  inst_o = {10'b0, rvc_inst[5], 1'b0, 2'b01, rs1_c,
                            3'b101, 2'b01, rd_c, 7'b0000011};
                end else begin
                  // C.LH -> lh rd', uimm(rs1')（funct3=001，有符号半字）
                  inst_o = {10'b0, rvc_inst[5], 1'b0, 2'b01, rs1_c,
                            3'b001, 2'b01, rd_c, 7'b0000011};
                end
                zcb_en_o = 1'b1;
              end
              3'b010: begin
                // C.SB -> sb rs2', uimm(rs1')（funct3=000）
                inst_o = {7'b0, 2'b01, rs2_c, 2'b01, rs1_c, 3'b000,
                          3'b0, rvc_inst[5], rvc_inst[6], 7'b0100011};
                zcb_en_o = 1'b1;
              end
              3'b011: begin
                if (rvc_inst[6] == 1'b0) begin
                  // C.SH -> sh rs2', uimm(rs1')（funct3=001，uimm={inst[5],0}）
                  inst_o = {7'b0, 2'b01, rs2_c, 2'b01, rs1_c, 3'b001,
                            3'b0, rvc_inst[5], 1'b0, 7'b0100011};
                end else begin
                  illegal_o = 1'b1;   // inst[6]=1 为保留编码
                end
                zcb_en_o = 1'b1;
              end
              default: illegal_o = 1'b1;   // 其余 C0 3'b100 编码保留
            endcase
          end
          default: illegal_o = 1'b1;   // C.FLD/C.LD/C.FSD/C.SD（无 F/非 RV64）
        endcase
      end

      // ================= 象限 1（CI/CL/CS）=================
      2'b01: begin
        unique case (funct3)
          3'b000: begin
            // C.ADDI -> addi rd, rd, imm（rd=x0 为 C.NOP/HINT -> NOP）
            inst_o = {{6{rvc_inst[12]}}, rvc_inst[12], rvc_inst[6:2],
                      rd, 3'b000, rd, 7'b0010011};
            if (rd == 5'b0) inst_o = `INST_NOP;
          end
          3'b001: begin
            // C.JAL（仅 RV32）-> jal x1, offset
            inst_o = {rvc_inst[12], rvc_inst[8], rvc_inst[10:9], rvc_inst[6],
                      rvc_inst[7], rvc_inst[2], rvc_inst[11], rvc_inst[5:3],
                      {9{rvc_inst[12]}}, 4'b0, ~rvc_inst[15], 7'b1101111};
          end
          3'b010: begin
            // C.LI -> addi rd, x0, imm（rd=x0 为 HINT -> NOP）
            inst_o = {{6{rvc_inst[12]}}, rvc_inst[12], rvc_inst[6:2], 5'b0,
                      3'b000, rd, 7'b0010011};
            if (rd == 5'b0) inst_o = `INST_NOP;
          end
          3'b011: begin
            // C.ADDI16SP（rd=x2）/ C.LUI（其余，rd=x0 为 HINT -> NOP）
            if (rd == 5'h02) begin
              // C.ADDI16SP -> addi x2, x2, nzimm<<4（nzimm=0 保留）
              inst_o = {{3{rvc_inst[12]}}, rvc_inst[4:3], rvc_inst[5], rvc_inst[2],
                        rvc_inst[6], 4'b0, 5'h02, 3'b000, 5'h02, 7'b0010011};
              if ({rvc_inst[12], rvc_inst[6:2]} == 6'b0) illegal_o = 1'b1;
            end else begin
              // C.LUI -> lui rd, imm
              inst_o = {{15{rvc_inst[12]}}, rvc_inst[6:2], rd, 7'b0110111};
              if (rd == 5'b0) inst_o = `INST_NOP;
            end
          end
          3'b100: begin
            // C.MISC-ALU（C1）：区分位为 inst[11:10]
            //   00/01: C.SRLI/C.SRAI（inst[10] 决定 srli/srai，inst[12]=1 保留）
            //   10:    C.ANDI
            //   11:    C.SUB/C.XOR/C.OR/C.AND（inst[12]&[6:5] 区分）
            unique case (rvc_inst[11:10])
              2'b00,
              2'b01: begin
                // C.SRLI（inst[10]=0）/ C.SRAI（inst[10]=1）
                // rd'=rs1'={01,inst[9:7]}（x8-x15 压缩编码）
                inst_o = {1'b0, rvc_inst[10], 5'b0, shamt, 2'b01, rs1_c,
                          3'b101, 2'b01, rs1_c, 7'b0010011};
                if (rvc_inst[12] == 1'b1) illegal_o = 1'b1;
              end
              2'b10: begin
                // C.ANDI（C1）：rd'=rs1'={01,inst[9:7]}
                inst_o = {{6{rvc_inst[12]}}, rvc_inst[12], rvc_inst[6:2], 2'b01, rs1_c,
                          3'b111, 2'b01, rs1_c, 7'b0010011};
              end
              2'b11: begin
                unique case ({rvc_inst[12], rvc_inst[6:5]})
                  3'b000: inst_o = {2'b01, 5'b0, 2'b01, rs2_c, 2'b01, rs1_c,
                                    3'b000, 2'b01, rs1_c, 7'b0110011};
                  3'b001: inst_o = {7'b0, 2'b01, rs2_c, 2'b01, rs1_c, 3'b100,
                                    2'b01, rs1_c, 7'b0110011};
                  3'b010: inst_o = {7'b0, 2'b01, rs2_c, 2'b01, rs1_c, 3'b110,
                                    2'b01, rs1_c, 7'b0110011};
                  3'b011: inst_o = {7'b0, 2'b01, rs2_c, 2'b01, rs1_c, 3'b111,
                                    2'b01, rs1_c, 7'b0110011};
                  3'b110: begin
                    // C.MUL（Zcb）-> mul rd', rd', rs2'（需 M 扩展）
                    inst_o = {7'b0000001, 2'b01, rs2_c, 2'b01, rs1_c, 3'b000,
                              2'b01, rs1_c, 7'b0110011};
                    zcb_en_o = 1'b1;
                  end
                  3'b111: begin
                    // Zcb 寄存器-立即数运算（rd'=inst[4:2] 区分）：
                    //   000=C.ZEXT.B  001=C.SEXT.B  010=C.ZEXT.H
                    //   011=C.SEXT.H  100=C.ZEXT.W(RV64)  101=C.NOT
                    unique case (rd_c)
                      3'b000: begin
                        // C.ZEXT.B -> andi rd', rd', 0xff
                        inst_o = {4'b0, 8'hff, 2'b01, rs1_c, 3'b111,
                                  2'b01, rs1_c, 7'b0010011};
                        zcb_en_o = 1'b1;
                      end
                      3'b001: begin
                        // C.SEXT.B -> sext.b rd', rd'（Zbb）
                        inst_o = {7'b0110000, 5'b00100, 2'b01, rs1_c, 3'b001,
                                  2'b01, rs1_c, 7'b0010011};
                        zcb_en_o = 1'b1;
                      end
                      3'b010: begin
                        // C.ZEXT.H -> zext.h rd', rd'（Zbb）
                        inst_o = {7'b0000100, 5'b0, 2'b01, rs1_c, 3'b100,
                                  2'b01, rs1_c, 7'b0110011};
                        zcb_en_o = 1'b1;
                      end
                      3'b011: begin
                        // C.SEXT.H -> sext.h rd', rd'（Zbb）
                        inst_o = {7'b0110000, 5'b00101, 2'b01, rs1_c, 3'b001,
                                  2'b01, rs1_c, 7'b0010011};
                        zcb_en_o = 1'b1;
                      end
                      3'b101: begin
                        // C.NOT -> xori rd', rd', -1
                        inst_o = {12'hfff, 2'b01, rs1_c, 3'b100,
                                  2'b01, rs1_c, 7'b0010011};
                        zcb_en_o = 1'b1;
                      end
                      default: illegal_o = 1'b1;   // C.ZEXT.W 仅 RV64
                    endcase
                  end
                  default: illegal_o = 1'b1;
                endcase
              end
              default: illegal_o = 1'b1;
            endcase
          end
          3'b101: begin
            // C.J -> jal x0, offset
            inst_o = {rvc_inst[12], rvc_inst[8], rvc_inst[10:9], rvc_inst[6],
                      rvc_inst[7], rvc_inst[2], rvc_inst[11], rvc_inst[5:3],
                      {9{rvc_inst[12]}}, 4'b0, ~rvc_inst[15], 7'b1101111};
          end
          3'b110, 3'b111: begin
            // C.BEQZ / C.BNEZ -> beq/bne rs1', x0, offset
            // funct3 位 [14:12] = {2'b00, inst[13]}：110(BEQZ)->000，111(BNEZ)->001
            inst_o = {{4{rvc_inst[12]}}, rvc_inst[6:5], rvc_inst[2], 5'b0, 2'b01,
                      rs1_c, 2'b00, rvc_inst[13], rvc_inst[11:10], rvc_inst[4:3],
                      rvc_inst[12], 7'b1100011};
          end
          default: illegal_o = 1'b1;
        endcase
      end

      // ================= 象限 2（CI/CR）=================
      2'b10: begin
        unique case (funct3)
          3'b000: begin
            // C.SLLI -> slli rd, rd, shamt（RV32 shamt[5]=1 保留）
            inst_o = {7'b0, shamt, rd, 3'b001, rd, 7'b0010011};
            if (rvc_inst[12] == 1'b1) illegal_o = 1'b1;
          end
          3'b010: begin
            // C.LWSP -> lw rd, imm(x2)（rd=x0 保留）
            inst_o = {4'b0, rvc_inst[3:2], rvc_inst[12], rvc_inst[6:4], 2'b00,
                      5'h02, 3'b010, rd, 7'b0000011};
            if (rd == 5'b0) illegal_o = 1'b1;
          end
          3'b100: begin
            // CR：C.JR / C.MV / C.EBREAK / C.JALR
            if (rvc_inst[12] == 1'b0) begin
              if (rs2 != 5'b0) begin
                // C.MV -> add rd, x0, rs2（rd=x0 为 HINT -> NOP）
                inst_o = {7'b0, rs2, 5'b0, 3'b000, rd, 7'b0110011};
                if (rd == 5'b0) inst_o = `INST_NOP;
              end else begin
                // C.JR -> jalr x0, rs1, 0（rs1=x0 保留）
                inst_o = {12'b0, rs1, 3'b000, 5'b0, 7'b1100111};
                if (rs1 == 5'b0) illegal_o = 1'b1;
              end
            end else begin
              if (rs2 != 5'b0) begin
                // C.ADD -> add rd, rd, rs2（rd=x0 为 HINT -> NOP）
                inst_o = {7'b0, rs2, rd, 3'b000, rd, 7'b0110011};
                if (rd == 5'b0) inst_o = `INST_NOP;
              end else begin
                if (rs1 == 5'b0) begin
                  // C.EBREAK -> ebreak
                  inst_o = 32'h00100073;
                end else begin
                  // C.JALR -> jalr x1, rs1, 0
                  inst_o = {12'b0, rs1, 3'b000, 5'b00001, 7'b1100111};
                end
              end
            end
          end
          3'b110: begin
            // C.SWSP -> sw rs2, imm(x2)
            inst_o = {4'b0, rvc_inst[8:7], rvc_inst[12], rvc_inst[6:2],
                      5'h02, 3'b010, rvc_inst[11:9], 2'b00, 7'b0100011};
          end
          3'b101: begin
            // Zcmp 压缩堆栈操作（C2 象限 [15:13]=101，与原保留的 C.FLDSP 空间重叠）。
            // 编码（规范 28.9/28.13，GCC 15.2 实测一致）：
            //   [12:8]=11000 cm.push / 11010 cm.pop / 11100 cm.popretz / 11110 cm.popret
            //           rlist=[7:4]，spimm=[3:2]
            //   [12:8]=011?? cm.mvsa01([6:5]=01) / cm.mva01s([6:5]=11)，rs1'=[9:7]，rs2'=[4:2]
            // 展开由 Zcmp_Expander FSM 完成；这里只做合法性识别。
            unique casez (rvc_inst[12:8])
              5'b11000, 5'b11010, 5'b11100, 5'b11110: begin
                if (rvc_inst[7:4] < 4'd4) illegal_o = 1'b1;   // rlist<4 保留
                else                      zcmp_en_o = 1'b1;
              end
              5'b011??: begin
                if (rvc_inst[6:5] == 2'b01 || rvc_inst[6:5] == 2'b11) begin
                  if (rvc_inst[9:7] == rvc_inst[4:2]) illegal_o = 1'b1;  // r1s'==r2s' 保留
                  else                                zcmp_en_o = 1'b1;
                end else begin
                  illegal_o = 1'b1;
                end
              end
              default: illegal_o = 1'b1;
            endcase
          end
          default: illegal_o = 1'b1;   // C.LDSP/C.FLWSP/C.SDSP（非 RV64/无 F）
        endcase
      end

      default: illegal_o = 1'b1;   // 32 位指令不应进入本模块
    endcase
  end

endmodule
