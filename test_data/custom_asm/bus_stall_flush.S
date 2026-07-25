# bus_stall_flush.S
#
# Bug: ~bus_ready flush destroys instruction in EX stage (no replay).
#
# When a bus access (address >= 0x8000_xxxx) is in MEM stage,
# bus_transfer=1 causes bus_ready=0 (in real SoC with AXI latency).
# Pipeline_Ctrl responds: id_ex_flush=1, ex_mem_flush=1, pc_stall, if_id_stall.
# The instruction currently in EX is permanently destroyed — no replay exists.
#
# In tb_core_top (bus_ready=1 always), this never triggers.
# In tb_soc_top (real AXI latency), UART/CLINT accesses trigger it.
# -O3 aggressive scheduling places critical ALU ops right after bus accesses.
#
# Test: store to bus address, immediately followed by ALU instructions.
# Expected (correct): x10 = 0x33333333
# Buggy behaviour:    x10 stays 0 (add was flushed from EX, never executed)

#include "riscv_test.h"
#undef RVTEST_RV64U
#define RVTEST_RV64U RVTEST_RV32U

  RVTEST_CODE_BEGIN

  # ---- Setup known values ----
  li   x1, 0x11111111
  li   x2, 0x22222222
  li   x10, 0              # result register (should become 0x33333333)
  li   x11, 0              # second result register

  # Bus address (>= 0x8000_0000 triggers bus_sel)
  lui  x5, 0x80000         # x5 = 0x8000_0000
  li   x6, 0xDEADBEEF     # store data

  # ---- Test 1: sw to bus, immediately followed by add ----
  # Pipeline timing:
  #   Cycle N:   sw in MEM (bus_transfer=1, bus_ready→0)
  #   Cycle N:   add in EX → FLUSHED by id_ex_flush!
  sw   x6, 0(x5)           # bus store
  add  x10, x1, x2        # should be x10=0x33333333, but gets flushed

  # padding to let bus transaction complete and pipeline resume
  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop

  # Check: x10 must equal 0x33333333
  li   x28, 0x33333333
  bne  x10, x28, fail

  # ---- Test 2: verify second instruction after bus store survives ----
  li   x10, 0
  li   x11, 0
  nop
  nop
  sw   x6, 4(x5)           # bus store
  add  x10, x1, x2        # in EX during flush → lost
  add  x11, x2, x1        # in ID during flush → survives (held in IF_ID)

  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop

  # x10 should be 0x33333333 (flushed → bug shows 0)
  li   x28, 0x33333333
  bne  x10, x28, fail
  # x11 should also be 0x33333333 (survives, always correct)
  bne  x11, x28, fail

  # ---- Test 3: bus LOAD followed by ALU ----
  li   x10, 0
  nop
  nop
  lw   x9, 0(x5)           # bus load (bus_transfer=1)
  add  x10, x1, x2        # in EX during flush → lost

  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop

  li   x28, 0x33333333
  bne  x10, x28, fail

  # ---- All tests passed ----
  li   x27, 1
  li   x26, 1
p: j p

fail:
  li   x27, 0
  li   x26, 1
fl: j fl

  RVTEST_CODE_END

  RVTEST_DATA_BEGIN
  RVTEST_DATA_END
