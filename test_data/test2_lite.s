# Breathing LED Test via PWM (polling mode)
# Timer Base: 0x80040000
# UART Base:  0x80010000
#
# PWM output compare logic (up-counting, polarity=0):
#   cmp_match  = (timer_cnt >= cmp_reg)
#   ext_out    = ~cmp_match  =>  HIGH when cnt < CCR, LOW when cnt >= CCR
#   cmp_reg is updated at timer_expired (end of each period)
#
# Breathing LED strategy:
#   ARR = 999 => period = 1000 timer-ticks per PWM cycle
#   PSC = 49   => prescaler div = 50 
#   Each PWM period: poll SR[0], update CCR1, change by step (+1 or -1)
#   CCR range: 0 (0% duty, LED off) ~ 999 (100% duty, LED fully on)
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

.eqv TIMER_BASE,  0x80040000
.eqv TIMx_PSC,    0x00
.eqv TIMx_CNT,    0x04
.eqv TIMx_ARR,    0x08
.eqv TIMx_CR,     0x0C
.eqv TIMx_IER,    0x10
.eqv TIMx_SR,     0x14
.eqv TIMx_CCMR,   0x18
.eqv TIMx_CCER,   0x1C
.eqv TIMx_CCR1,   0x20
.eqv UART_BASE,   0x80010000
.eqv UART_THR,    0x00             # UART Transmit Holding Register

    .text
    .align 4
    .global _start

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

    # Set PSC = 1 (prescaler divides by 2; PSC=0 is reserved)
    li t1, 1
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
    #   value = 0x00000001
    li t1, 0x01
    sw t1, TIMx_CCMR(t0)

    # Configure CCER:
    #   timer_ic_oc_en      [3:0] = 0001 -> ch0 enabled
    #   timer_ic_oc_polarity[7:4] = 0000 -> ch0 high-active (output HIGH when cnt < CCR)
    #   timer_trigger_mode [15:8] = 0    -> not used for output compare
    #   value = 0x00000001
    li t1, 0x01
    sw t1, TIMx_CCER(t0)

    # NOTE: No interrupt setup needed. We poll SR[0] directly to detect overflow.

    # Start timer (up-counting): CR[0]=timer_en=1, CR[1]=timer_clr=0, CR[2]=dir=0
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

    # ---- Update CCR1 for next period ----
    # Update direction:
    #   if increasing (s2==0) and CCR1 == 999 -> switch to decreasing
    #   if decreasing (s2==1) and CCR1 == 0   -> switch to increasing
    li t3, 999
    beqz s2, check_top      # s2==0 -> check upper bound
    # s2==1 (decreasing): check if CCR1 == 0
    beqz s1, set_increasing
    addi s1, s1, -1         # CCR1 -= 1
    j update_ccr

check_top:
    bne s1, t3, do_increase # CCR1 != 999 -> keep increasing
    li s2, 1                # Switch to decreasing
    addi s1, s1, -1         # CCR1 -= 1 (first step down)
    j update_ccr

do_increase:
    addi s1, s1, 1          # CCR1 += 1
    j update_ccr

set_increasing:
    li s2, 0                # Switch to increasing
    addi s1, s1, 1          # CCR1 += 1 (first step up)

update_ccr:
    # Write new CCR1 (takes effect at next timer_expired)
    sw s1, TIMx_CCR1(s0)

    j breathing_loop
    nop
    nop
