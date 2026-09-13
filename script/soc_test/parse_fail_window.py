#!/usr/bin/env python3
# 解析 fail_trace.vcd：mcause=4 前后数据通路表（含 stall/flush）
import sys

VCD = r"D:/Desktop/OpenClaw_Workspace/RISCV_CPU/Working/logs/fail_trace.vcd"
MC4_T = 66056089000
LO = MC4_T - 70 * 8000
HI = MC4_T + 8 * 8000

# 头部
bits = {}
vecs = {}
clk_id = None
with open(VCD, errors='replace') as f:
    for line in f:
        line = line.strip()
        if line.startswith('$var'):
            p = line.split()
            wid, base = p[3], p[4]
            rng = p[5] if len(p) >= 6 else ''
            if rng.startswith('[') and ':' in rng:
                vecs[wid] = base
            elif rng.startswith('['):
                bits[wid] = (base, int(rng.strip('[]')))
            elif base == 'clk':
                clk_id = wid
        elif line.startswith('$enddefinitions'):
            break

sig_bits = {}
for wid, (base, idx) in bits.items():
    sig_bits.setdefault(base, {})[idx] = wid
sig_vec = dict(vecs)

def get(d, name):
    if name in sig_vec:
        s = d.get(sig_vec[name])
        if s is None or 'x' in s or 'z' in s:
            return None
        return int(s, 2)
    if name in sig_bits:
        v = 0
        for idx, wid in sig_bits[name].items():
            b = d.get(wid, 'x')
            if b not in '01':
                return None
            v |= int(b) << idx
        return v
    return None

def hx(v):
    return f"{v:08x}" if v is not None else "xxxxxxxx"

def b(v):
    return "?" if v is None else str(v)

NAMES = ['pc', 'inst_ex', 'access_addr_ex', 'access_en_ex', 'access_wr_ex',
         'dtcm_addr_sba', 'dtcm_rdata', 'tcm_rvalid', 'func3_expanded_data',
         'reg_rd_wdata_mem', 'reg_rd_wen_mem', 'reg_rd_wdata_selected_mem',
         'reg_rd_waddr_mem', 'alu_op1_forward', 'ex_mem_stall', 'ex_mem_flush',
         'id_ex_flush', 'id_ex_stall', 'mcause']

state = {}
snap = {}
cur_t = None
prev_clk = '0'
clk_v = '0'
rows = []
in_defs = True
mc4_first = None

with open(VCD, errors='replace') as f:
    for line in f:
        line = line.strip()
        if in_defs:
            if line.startswith('$enddefinitions'):
                in_defs = False
            continue
        if not line:
            continue
        if line[0] == '#':
            if cur_t is not None and prev_clk == '0' and clk_v == '1':
                mc = get(snap, 'mcause')
                if mc == 4 and mc4_first is None:
                    mc4_first = cur_t
                if LO <= cur_t <= HI:
                    row = {n: get(snap, n) for n in NAMES}
                    rows.append((cur_t, row))
            prev_clk = clk_v
            clk_v = state.get(clk_id, '0')
            snap = dict(state)
            cur_t = int(line[1:])
            if mc4_first is not None and cur_t > mc4_first + 10 * 8000:
                break
            continue
        if line[0] in '01xz' and len(line) >= 2:
            state[line[1:]] = line[0]
        elif line[0] == 'b':
            val, _, wid = line[1:].partition(' ')
            state[wid] = val

print(f"mcause=4 首次(绝对 ps): {mc4_first}")
print(f"{'t(ns)':>13} {'pc':>8} {'inst_x':>8} {'acc_addr':>8} {'en':>2} {'wr':>2} {'port':>8} {'rd':>8} {'rv':>2} {'f3':>8} {'wd_m':>8} {'we_m':>3} {'sel_d':>8} {'wa_m':>4} {'op1f':>8} {'eS':>2} {'eF':>2} {'iF':>2} {'iS':>2} {'mc':>8}")
for t, r in rows:
    print(f"{t:>13} {hx(r['pc']):>8} {hx(r['inst_ex']):>8} {hx(r['access_addr_ex']):>8} {b(r['access_en_ex']):>2} {b(r['access_wr_ex']):>2} {hx(r['dtcm_addr_sba']):>8} {hx(r['dtcm_rdata']):>8} {b(r['tcm_rvalid']):>2} {hx(r['func3_expanded_data']):>8} {hx(r['reg_rd_wdata_mem']):>8} {b(r['reg_rd_wen_mem']):>3} {hx(r['reg_rd_wdata_selected_mem']):>8} {b(r['reg_rd_waddr_mem']):>4} {hx(r['alu_op1_forward']):>8} {b(r['ex_mem_stall']):>2} {b(r['ex_mem_flush']):>2} {b(r['id_ex_flush']):>2} {b(r['id_ex_stall']):>2} {hx(r['mcause']):>8}")
