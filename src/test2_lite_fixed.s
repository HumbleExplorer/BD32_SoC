# Breathing LED Test via PWM (polling mode)
# Timer Base: 0xE0040000
# CLINT Base: 0xF2000000 (4KB block)
# UART Base:  0xE0010000
#
# PWM output compare logic (up-counting, polarity=0):
#   cmp_match  = (timer_cnt >= cmp_reg)
#   ext_out    = ~cmp_match  =>  HIGH when cnt < CCR, LOW when cnt >= CCR
#   cmp_reg is updated at timer_expired (end of each period)
#
# Breathing LED strategy:
#   ARR = 999 => period = 1000 timer-ticks per PWM cycle
#   PSC = 49   => prescaler div = 50
#   Each PWM period: update CCR1, delay 10ms, change by step (+1 or -1)
#   CCR range: 0 (0% duty, LED off) ~ 999 (100% duty, LED fully on)
#
# CLINT mtime delay:
#   10ms @ 50MHz = 500000 cycles
#   Strategy: set mtimecmp = mtime + 500000, then poll mtime until reached
#
# Register bit fields (CHANNEL_NUM=4):
#
# TIMx_CR  [0]=timer_en, [1]=timer_clr, [2]=timer_dir_sel(0=up,1=down)
# TIMx_IER [0]=timer_int_en, [1]=timer_of_int_en, [5:2]=timer_ic_oc_int_en[3:0]
# TIMx_SR  [0]=timer_int_of_pend (write-1-to-clear), [4:1]=timer_int_trigger_pend
# TIMx_CCMR
#   [3:0]   = timer_ic_oc_mode[3:0]  (1bit/ch, 0=capture, 1=output-compare)
#   [19:4]  = timer_filter_mode[15:0] (4bits/ch)
# TIMx_CCER
#   [3:0]   = timer_ic_oc_en[3:0]       (1bit/ch, enable)
#   [7:4]   = timer_ic_oc_polarity[3:0] (1bit/ch, 0=high-active output)
#   [15:8]  = timer_trigger_mode[7:0]   (2bits/ch)

.eqv TIMER_BASE,    0xE0020000
.eqv TIMx_PSC,      0x00
.eqv TIMx_CNT,      0x04
.eqv TIMx_ARR,      0x08
.eqv TIMx_CR,       0x0C
.eqv TIMx_IER,      0x10
.eqv TIMx_SR,       0x14
.eqv TIMx_CCMR,     0x18
.eqv TIMx_CCER,     0x1C
.eqv TIMx_CCR1,     0x20
.eqv MTIME_ADDR,    0xF200BFF8
.eqv MTIMECMP_ADDR, 0xF2004000
.eqv UART_BASE,     0xE0010000
.eqv UART_THR,      0x00        # UART Transmit Holding Register
# 10ms @ 100MHz = 500000 cycles
.eqv DELAY_10MS,    500000

    .text
    .align 4
    .global _start

# ======================================================================
# _start: entry point (must be at the lowest address in .text)
# mrom.s jumps to 0x00010000 (ITCM base) which lands exactly here
# ======================================================================
_start:
    # ----------------------------------------------------------------
    # Step 0: Print welcome text from DTCM (0x00020000 ~ 0x000200a0)
    # ----------------------------------------------------------------
    li  t0, UART_BASE               # UART base address
    li  t1, 0x00020000              # DTCM start address (welcome text)
    li  t2, 0x000200a0              # DTCM end address

print_welcome:
    lb  t3, 0(t1)                   # Load byte from DTCM
    sw  t3, UART_THR(t0)            # Write to UART THR
    addi t1, t1, 4                  # Next word (word-aligned)
    bne t1, t2, print_welcome       # Not end -> continue
    nop

    # ----------------------------------------------------------------
    # Step 1: Configure Timer
    # ----------------------------------------------------------------
    li t0, TIMER_BASE

    # Set PSC = 99 (prescaler divides by 100)
    li t1, 99
    sw t1, TIMx_PSC(t0)

    # Set ARR = 999 (up-counting: overflow at cnt==999, period=1000 ticks)
    li t1, 999
    sw t1, TIMx_ARR(t0)

    # Set initial CCR1 = 0 (0% duty cycle, LED off at start)
    li t1, 0
    sw t1, TIMx_CCR1(t0)

    # Configure CCMR:
    #   timer_ic_oc_mode  [3:0] = 0001 -> ch0=output-compare, ch1-3=capture
    #   timer_filter_mode[19:4] = 0    -> no filter
    li t1, 0x01
    sw t1, TIMx_CCMR(t0)

    # Configure CCER:
    #   timer_ic_oc_en      [3:0] = 0001 -> ch0 enabled
    #   timer_ic_oc_polarity[7:4] = 0000 -> ch0 high-active
    li t1, 0x01
    sw t1, TIMx_CCER(t0)

    # Start timer (up-counting): CR[0]=timer_en=1
    li t1, 0x01
    sw t1, TIMx_CR(t0)

    # ----------------------------------------------------------------
    # Step 2: Breathing LED main loop
    #   s0 = TIMER_BASE
    #   s1 = current CCR1 value (0..999)
    #   s2 = direction: 0=increasing, 1=decreasing
    # ----------------------------------------------------------------
    mv s0, t0
    li s1, 0        # CCR1 starts at 0
    li s2, 0        # direction = increasing

breathing_loop:
    # ---- Update direction ----
    li t3, 999
    beqz s2, check_top          # s2==0 -> check upper bound
    # s2==1 (decreasing): check if CCR1 == 0
    beqz s1, set_increasing
    addi s1, s1, -1             # CCR1 -= 1
    j update_ccr

check_top:
    bne s1, t3, do_increase     # CCR1 != 999 -> keep increasing
    li s2, 1                    # Switch to decreasing
    addi s1, s1, -1             # CCR1 -= 1 (first step down)
    j update_ccr

do_increase:
    addi s1, s1, 1              # CCR1 += 1
    j update_ccr

set_increasing:
    li s2, 0                    # Switch to increasing
    addi s1, s1, 1              # CCR1 += 1 (first step up)

update_ccr:
    # Write new CCR1 (takes effect at next timer_expired)
    sw s1, TIMx_CCR1(s0)

    # Delay 10ms between each PWM step (via CLINT mtimecmp)
    # Each brightness step lasts 10ms -> full breath ~20s (999 steps x 2)
    call delay_10ms

    j breathing_loop
    nop

# ======================================================================
# delay_10ms: blocking delay using CLINT mtimecmp
#   Placed AFTER _start so that 0x00010000 lands on _start, not here.
#   - Reads current mtime (low 32 bits), adds 500000, writes to mtimecmp
#   - Polls mtime until mtime >= target
#   - 10ms @ 50MHz = exactly 500000 clock cycles
#   - Clobbers: t0, t1, t2, t3, t4
# ======================================================================
delay_10ms:
    # Step 1: Read current mtime[31:0]
    li   t0, MTIME_ADDR
    lw   t1, 0(t0)                # t1 = current mtime[31:0] (pseudo: lui+lw)

    # Step 2: target = mtime + 500000
    li   t2, DELAY_10MS
    add  t3, t1, t2                    # t3 = target

    # Step 3: (no mtimecmp write - no interrupt handler installed)
    # sw   t3, MTIMECMP_ADDR

    # Step 4: Poll mtime until it reaches target
poll_mtime:
    lw   t4, 0(t0)                # t4 = current mtime[31:0]
    blt  t4, t3, poll_mtime            # if mtime < target, keep polling
    ret
