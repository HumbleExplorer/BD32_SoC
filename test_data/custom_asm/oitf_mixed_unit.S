# OITF mixed-unit ordering test.
#
# Exposes the bug in OITF.sv where raw_hazard / waw_hit use
#   ~oitf_cur[j].ready
# as the stall condition. Once an OITF entry is `ready` (result computed) the
# dependent instruction is released -- but forwarding (lp_retire_wdata) only
# supplies the FIFO-HEAD entry's data at retire time. So if a YOUNGER fast MUL
# entry is `ready` while an OLDER slow DIV entry is still ahead of it in the
# FIFO (cannot retire yet), a dependent instruction on the MUL's result proceeds
# and reads STALE register-file data instead of the MUL result.
#
# Pure register ops, runs directly in tb_core_top (no UART).
# Pass: x27==1.  Fail: x27 = 2 (raw) or 3 (waw).
#
#include "riscv_test.h"
#undef RVTEST_RV64U
#define RVTEST_RV64U RVTEST_RV32U

  RVTEST_CODE_BEGIN

  # =====================================================================
  # Scenario 1: RAW on the YOUNGER MUL while the OLDER DIV is still in OITF
  # =====================================================================
  # DIV first -> OITF entry0 (unit1, slow), writes x20 = 14
  li   x2, 100
  li   x3, 7
  div  x20, x2, x3

  # MUL next -> OITF entry1 (unit0, fast, 3-cycle), writes x21 = 30
  li   x4, 5
  li   x5, 6
  mul  x21, x4, x5

  # A few independent instructions so the MUL is `ready` (but NOT retired,
  # because the older DIV still blocks the FIFO head) before the dependent
  # add reaches EX.
  li   x7, 1
  li   x8, 2
  li   x9, 3
  li   x10, 4
  li   x11, 5

  # Depend ONLY on the MUL result x21 (NOT on x20 / the DIV).
  # Buggy RTL: MUL entry is ready -> raw_hazard=false -> add proceeds and
  #            reads stale regfile[x21]=0  -> x22 = 100 (wrong).
  # Fixed RTL: add stalls until MUL entry retires (after DIV) and is correctly
  #            forwarded the MUL result 30 -> x22 = 130.
  li   x6, 100
  add  x22, x21, x6
  li   x13, 130
  bne  x22, x13, fail_raw

  # =====================================================================
  # Scenario 2: WAW -- younger write to x21 after the MUL, DIV still pending
  # =====================================================================
  li   x2, 200
  li   x3, 9
  div  x20, x2, x3      # x20 = 22 (entry0, slow)
  li   x4, 8
  li   x5, 11
  mul  x21, x4, x5      # x21 = 88 (entry1, fast)

  li   x7, 1
  li   x8, 2
  li   x9, 3
  li   x10, 4

  # Younger write to x21 (WAW): must be the FINAL value.
  li   x21, 0xABCDEF01

  # Force the pipeline to wait until the OLDER DIV retires (which also retires
  # the MUL, since FIFO). Only then is the MUL's port2 write done.
  add  x14, x20, x0     # RAW on x20 (DIV) -> stalls until DIV retires

  # Buggy RTL: li x21 wrote 0xABCDEF01 early (port1), then MUL retired later
  #            (port2) and overwrote x21 = 88 -> mismatch.
  # Fixed RTL: li x21 was stalled until MUL retired -> final x21 = 0xABCDEF01.
  li   x13, 0xABCDEF01
  bne  x21, x13, fail_waw

  # all passed
  li x26, 1
  li x27, 1
pass_loop:
  j pass_loop

fail_raw: li x26,1; li x27,2; li gp,2;  j fail_loop
fail_waw: li x26,1; li x27,3; li gp,3;  j fail_loop
fail_loop:
  j fail_loop

  RVTEST_CODE_END

  RVTEST_DATA_BEGIN
  RVTEST_DATA_END
