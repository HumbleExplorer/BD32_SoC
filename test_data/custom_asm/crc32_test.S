# crc32_test.S - coremark-style CRC32 table lookup (common path for all 3 CRCs).
# Table init via sw to DTCM@0x1A000 (CORE_TEST .data not auto-loaded).
# Buffer '123456789' @0x1B000. Expected CRC32 = 0xCBF43926.

#include "riscv_test.h"
#undef RVTEST_RV64U
#define RVTEST_RV64U RVTEST_RV32U

  RVTEST_CODE_BEGIN

  # ---- init CRC table at 0x1A000 ----
  li x2, 0x1A000
  li x3, 0
tbl_init_loop:
  li x4, 256
  bge x3, x4, tbl_init_done
  mv x5, x3            # c = i
  li x6, 0             # j = 0
tbl_bit_loop:
  li x7, 8
  bge x6, x7, tbl_bit_done
  andi x8, x5, 1       # c & 1
  beq x8, x0, tbl_shr
  lui x11, 0xEDB88
  addi x11, x11, 0x320  # x11 = 0xEDB88320
  srli x9, x5, 1
  xor x5, x11, x9       # c = 0xEDB88320 ^ (c>>1)
  j tbl_bit_next
tbl_shr:
  srli x5, x5, 1        # c = c>>1
tbl_bit_next:
  addi x6, x6, 1
  j tbl_bit_loop
tbl_bit_done:
  slli x12, x3, 2       # i*4
  add x13, x2, x12      # &table[i]
  sw x5, 0(x13)         # table[i] = c
  addi x3, x3, 1
  j tbl_init_loop
tbl_init_done:
  # ---- init buffer at 0x1B000: '123456789' ----
  li x14, 0x1B000
  li x15, 49
  sb x15, 0(x14)
  li x15, 50
  sb x15, 1(x14)
  li x15, 51
  sb x15, 2(x14)
  li x15, 52
  sb x15, 3(x14)
  li x15, 53
  sb x15, 4(x14)
  li x15, 54
  sb x15, 5(x14)
  li x15, 55
  sb x15, 6(x14)
  li x15, 56
  sb x15, 7(x14)
  li x15, 57
  sb x15, 8(x14)

  # ---- crc32 over buffer (9 bytes) ----
  li x16, 0x1B000      # buf ptr
  li x17, 9            # len
  li x18, 0xFFFFFFFF   # crc = ~0
crc_loop:
  beq x17, x0, crc_done
  lbu x19, 0(x16)      # b = buf[i]
  xor x20, x18, x19    # crc ^ b
  andi x20, x20, 0xFF  # & 0xff -> index
  slli x21, x20, 2     # index*4
  add x22, x2, x21     # &table[index]
  lw x23, 0(x22)       # table[index]  <-- CRC TABLE LOOKUP
  srli x24, x18, 8     # crc >> 8
  xor x18, x23, x24    # crc = table[index] ^ (crc>>8)
  addi x16, x16, 1
  addi x17, x17, -1
  j crc_loop
crc_done:
  not x18, x18         # crc = ~crc
  li x25, 0xCBF43926
  bne x18, x25, failCRC

  li x26, 1
  li x27, 1
pass_loop:
  j pass_loop
failCRC:
  li x26, 1
  li x27, 0
  li gp, 40
fail_loop:
  j fail_loop

  RVTEST_CODE_END
  RVTEST_DATA_BEGIN
  RVTEST_DATA_END
