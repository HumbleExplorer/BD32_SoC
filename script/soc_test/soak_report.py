#!/usr/bin/env python3
# soak 报告：SERR 计数 / marker / t1-t2 健康 / 时间跨度 → logs/soak_report.txt
# 全部路径由脚本自身位置推导并锚定在仓库内，无任何外部输入
import re, time
from pathlib import Path
_REPO = Path(__file__).resolve().parents[2]
LOG = _REPO / "logs" / "soak_uart.log"
MARK = _REPO / "logs" / "soak_SERR_FOUND.marker"
OUT = _REPO / "logs" / "soak_report_8am.txt"
# 输出锚定校验：报告只允许写进本仓库 logs/ 内
if _REPO not in OUT.resolve().parents:
    raise SystemExit("report path escapes repository")
s = LOG.read_text(encoding="utf-8", errors="replace") if LOG.exists() else ""
lines = s.splitlines()
t1 = sum(1 for l in lines if l.strip() == "t1")
t2 = sum(1 for l in lines if l.strip() == "t2")
serr = [i for i, l in enumerate(lines) if "SERR" in l]
span = ""
m = re.findall(r"===== soak (start|end) ([^=]+) =====", s)
if m:
    span = f"{m[0][1]} → {m[-1][1]}"
verdict = "PASS（无 SERR，线程持续交替）" if not serr and (t1 + t2) > 1000 else "FAIL（见上）"
report = (
    f"=== BD32 soak 8 点报告（{time.strftime('%Y-%m-%d %H:%M:%S')}）===\n"
    f"时间跨度: {span}\n"
    f"t1 打印: {t1} 行, t2 打印: {t2} 行\n"
    f"SERR 出现: {len(serr)} 次（行号 {serr[:5]}）\n"
    f"marker 文件: {'存在' if MARK.exists() else '无'}\n"
    f"结论: {verdict}\n")
OUT.write_text(report, encoding="utf-8")
print("report written")
