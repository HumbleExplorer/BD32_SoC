#!/usr/bin/env python3
# 8 点 soak 报告：SERR 计数 / marker / t1-t2 健康 / 时间跨度 → logs/soak_report_8am.txt
import os, re, time
LOG = r"D:\Desktop\OpenClaw_Workspace\RISCV_CPU\Working\logs\soak_uart.log"
MARK = LOG.replace("soak_uart.log", "soak_SERR_FOUND.marker")
OUT = r"D:\Desktop\OpenClaw_Workspace\RISCV_CPU\Working\logs\soak_report_8am.txt"
s = open(LOG, encoding="utf-8", errors="replace").read() if os.path.exists(LOG) else ""
lines = s.splitlines()
t1 = sum(1 for l in lines if l.strip() == "t1")
t2 = sum(1 for l in lines if l.strip() == "t2")
serr = [i for i, l in enumerate(lines) if "SERR" in l]
span = ""
m = re.findall(r"===== soak (start|end) ([^=]+) =====", s)
if m:
    span = f"{m[0][1]} → {m[-1][1]}"
verdict = "PASS（无 SERR，线程持续交替）" if not serr and (t1 + t2) > 1000 else "FAIL（见上）"
with open(OUT, "w", encoding="utf-8") as f:
    f.write(f"=== BD32 soak 8 点报告（{time.strftime('%Y-%m-%d %H:%M:%S')}）===\n")
    f.write(f"时间跨度: {span}\n")
    f.write(f"t1 打印: {t1} 行, t2 打印: {t2} 行\n")
    f.write(f"SERR 出现: {len(serr)} 次（行号 {serr[:5]}）\n")
    f.write(f"marker 文件: {'存在' if os.path.exists(MARK) else '无'}\n")
    f.write(f"结论: {verdict}\n")
print("report written")
