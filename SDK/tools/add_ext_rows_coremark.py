"""
把扩展 ISA 的 CoreMark 结果按原格式追加进 BD32_CoreMark_Compiler_Comparison.xlsx：
- 主表：在现有 23 行后追加扩展行（行 28 起），优化选项列标注扩展 march
- 归一化对比：扩展行体积/性能比以 原表 GCC O2 为基准（newlib→newlib，picolibc→picolibc）
- 说明区：追加扩展段说明
运行：python SDK/tools/add_ext_rows_coremark.py
"""
import json
import os

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
RUN = os.path.join(ROOT, "SDK", "demos", "newlib", "coremark", "build_ext", "run_results.json")
XLSX = os.path.join(ROOT, "BD32_CoreMark_Compiler_Comparison.xlsx")

# 行顺序：(key, 扩展段标签, libc, 备注)
ROWS = [
    ("ext_c_newlib_gcc", "C", "newlib-nano", "扩展: rv32imc (RV32C)"),
    ("ext_c_zcb_newlib_gcc", "C+Zcb", "newlib-nano", "扩展: rv32imc_zcb"),
    ("ext_c_b_newlib_gcc", "C+B", "newlib-nano", "扩展: rv32imc_zba_zbb_zbs"),
    ("ext_c_zcmp_newlib_gcc", "C+Zcmp", "newlib-nano", "扩展: rv32imc_zcmp"),
    ("ext_c_b_zicond_newlib_gcc", "C+B+Zicond", "newlib-nano", "扩展: rv32imc_zba_zbb_zbs_zicond"),
    ("ext_c_full_newlib_gcc", "C+Zcb+B+Zcmp+Zicond", "newlib-nano", "扩展: rv32imc_zcb_zba_zbb_zbs_zcmp_zicond"),
    ("ext_c_newlib_llvm", "C", "newlib-nano", "扩展: rv32imc (RV32C)"),
    ("ext_c_zcb_newlib_llvm", "C+Zcb", "newlib-nano", "扩展: rv32imc_zcb"),
    ("ext_c_b_newlib_llvm", "C+B", "newlib-nano", "扩展: rv32imc_zba_zbb_zbs"),
    ("ext_c_zcmp_newlib_llvm", "C+Zcmp", "newlib-nano", "扩展: rv32imc_zcmp"),
    ("ext_c_b_zicond_newlib_llvm", "C+B+Zicond", "newlib-nano", "扩展: rv32imc_zba_zbb_zbs_zicond"),
    ("ext_c_newlib_llvm".replace("newlib_llvm", "picolibc_llvm"), "", "", ""),
]
# 重写：完整 21 行（5 组合×4 编译配置 + 全扩展 1）
ROWS = [
    ("ext_c_newlib_gcc",          "C",                "newlib-nano",  "扩展: rv32imc (RV32C)"),
    ("ext_c_zcb_newlib_gcc",      "C+Zcb",            "newlib-nano",  "扩展: rv32imc_zcb"),
    ("ext_c_b_newlib_gcc",        "C+B",              "newlib-nano",  "扩展: rv32imc_zba_zbb_zbs"),
    ("ext_c_zcmp_newlib_gcc",     "C+Zcmp",           "newlib-nano",  "扩展: rv32imc_zcmp"),
    ("ext_c_b_zicond_newlib_gcc", "C+B+Zicond",       "newlib-nano",  "扩展: rv32imc_zba_zbb_zbs_zicond"),
    ("ext_c_full_newlib_gcc",     "C+Zcb+B+Zcmp+Zi",  "newlib-nano",  "扩展: rv32imc_zcb_zba_zbb_zbs_zcmp_zicond (全扩展)"),
    ("ext_c_newlib_llvm",         "C",                "newlib-nano",  "扩展: rv32imc (RV32C)"),
    ("ext_c_zcb_newlib_llvm",     "C+Zcb",            "newlib-nano",  "扩展: rv32imc_zcb"),
    ("ext_c_b_newlib_llvm",       "C+B",              "newlib-nano",  "扩展: rv32imc_zba_zbb_zbs"),
    ("ext_c_zcmp_newlib_llvm",    "C+Zcmp",           "newlib-nano",  "扩展: rv32imc_zcmp"),
    ("ext_c_b_zicond_newlib_llvm","C+B+Zicond",       "newlib-nano",  "扩展: rv32imc_zba_zbb_zbs_zicond"),
    ("ext_c_newlib_gcc",          "C",                "picolibc",     "占位(不会用到)"),
]
# 直接按 21 配置手写清楚（避免歧义）
def key(tag, libc, cc): return f"{tag}_{libc}_{cc}"
ROWS = [
    (key("ext_c",          "newlib",   "gcc"),  "C",              "newlib-nano", "扩展: rv32imc (RV32C)"),
    (key("ext_c_zcb",      "newlib",   "gcc"),  "C+Zcb",          "newlib-nano", "扩展: rv32imc_zcb"),
    (key("ext_c_b",        "newlib",   "gcc"),  "C+B",            "newlib-nano", "扩展: rv32imc_zba_zbb_zbs"),
    (key("ext_c_zcmp",     "newlib",   "gcc"),  "C+Zcmp",         "newlib-nano", "扩展: rv32imc_zcmp"),
    (key("ext_c_b_zicond", "newlib",   "gcc"),  "C+B+Zicond",     "newlib-nano", "扩展: rv32imc_zba_zbb_zbs_zicond"),
    (key("ext_c_full",     "newlib",   "gcc"),  "C+Zcb+B+Zcmp+Zi","newlib-nano", "扩展: rv32imc_zcb_zba_zbb_zbs_zcmp_zicond (全扩展)"),
    (key("ext_c",          "picolibc", "gcc"),  "C",              "picolibc",    "扩展: rv32imc (RV32C)"),
    (key("ext_c_zcb",      "picolibc", "gcc"),  "C+Zcb",          "picolibc",    "扩展: rv32imc_zcb"),
    (key("ext_c_b",        "picolibc", "gcc"),  "C+B",            "picolibc",    "扩展: rv32imc_zba_zbb_zbs"),
    (key("ext_c_zcmp",     "picolibc", "gcc"),  "C+Zcmp",         "picolibc",    "扩展: rv32imc_zcmp"),
    (key("ext_c_b_zicond", "picolibc", "gcc"),  "C+B+Zicond",     "picolibc",    "扩展: rv32imc_zba_zbb_zbs_zicond"),
    (key("ext_c",          "newlib",   "llvm"), "C",               "newlib-nano", "扩展: rv32imc (RV32C)"),
    (key("ext_c_zcb",      "newlib",   "llvm"), "C+Zcb",          "newlib-nano", "扩展: rv32imc_zcb"),
    (key("ext_c_b",        "newlib",   "llvm"), "C+B",            "newlib-nano", "扩展: rv32imc_zba_zbb_zbs"),
    (key("ext_c_zcmp",     "newlib",   "llvm"), "C+Zcmp",         "newlib-nano", "扩展: rv32imc_zcmp"),
    (key("ext_c_b_zicond", "newlib",   "llvm"), "C+B+Zicond",     "newlib-nano", "扩展: rv32imc_zba_zbb_zbs_zicond"),
    (key("ext_c",          "picolibc", "llvm"), "C",               "picolibc",    "扩展: rv32imc (RV32C)"),
    (key("ext_c_zcb",      "picolibc", "llvm"), "C+Zcb",          "picolibc",    "扩展: rv32imc_zcb"),
    (key("ext_c_b",        "picolibc", "llvm"), "C+B",            "picolibc",    "扩展: rv32imc_zba_zbb_zbs"),
    (key("ext_c_zcmp",     "picolibc", "llvm"), "C+Zcmp",         "picolibc",    "扩展: rv32imc_zcmp"),
    (key("ext_c_b_zicond", "picolibc", "llvm"), "C+B+Zicond",     "picolibc",    "扩展: rv32imc_zba_zbb_zbs_zicond"),
]
# run_results.json 里的 key 是 无 zcb 前缀的 5 组合
def norm_key(tag, libc, cc):
    m = {"ext_c": "ext_c", "ext_c_zcb": "ext_c_zcb", "ext_c_b": "ext_c_b",
         "ext_c_zcmp": "ext_c_zcmp", "ext_c_b_zicond": "ext_c_b_zicond",
         "ext_c_full": "ext_c_full"}
    return f"{m[tag]}_{libc}_{cc}"


def main():
    data = json.load(open(RUN))
    import openpyxl
    from openpyxl.styles import Font
    wb = openpyxl.load_workbook(XLSX)
    ws = wb["BD32编译器优化对比"]
    bold = Font(bold=True)

    # 找原主表最后一行（行 5..27）
    last_main = 27
    start = last_main + 1  # 行 28 起

    # 原 基准行：newlib GCC O2 = 行 7， picolibc GCC O2 = 行 16
    base_rows = {"newlib-nano": 7, "picolibc": 16}

    # ---- 主表追加 ----
    main_rows = []
    for i, (k, seg, libc, note) in enumerate(ROWS):
        r = data.get(k)
        if not r:
            print(f"[WARN] 无结果: {k}")
            continue
        row = start + len(main_rows)
        main_rows.append(row)
        cc_label = "LLVM" if "llvm" in k else "GCC"
        march_extra = note.split("扩展: ")[1]
        ws.cell(row, 1, len(main_rows) + 23)          # 序号 24..
        ws.cell(row, 2, cc_label)
        ws.cell(row, 3, libc)
        ws.cell(row, 4, "-O2  -march=" + march_extra + " -mabi=ilp32")
        ws.cell(row, 5, r["itcm"])
        ws.cell(row, 6, r["dtcm"])
        ws.cell(row, 7, f"=(E{row}+F{row})*4")
        ws.cell(row, 8, r["cm"])
        ws.cell(row, 9, r["ips"])
        ws.cell(row, 10, r["ticks"])
        ws.cell(row, 11, round(r["br"], 2) if r.get("br") else "")
        ws.cell(row, 12, note)

    # ---- 归一化追加（紧跟主表扩展段）----
    norm_title_row = start + len(main_rows) + 2
    ws.cell(norm_title_row, 1, "扩展段归一化对比（以各 C 库原表 GCC -O2 为基准 = 1.00）").font = bold
    norm_hdr = norm_title_row + 1
    for j, h in enumerate(["序号", "编译器", "C库", "扩展段", "体积比(vs 原O2)",
                           "性能比(vs 原O2)", "性价比(性能/体积)"], 1):
        ws.cell(norm_hdr, j, h).font = bold
    for i, (k, seg, libc, note) in enumerate(ROWS):
        r = data.get(k)
        if not r:
            continue
        src_row = start + i
        dst_row = norm_hdr + 1 + i
        base = base_rows[libc]
        cc_label = "LLVM" if "llvm" in k else "GCC"
        ws.cell(dst_row, 1, i + 1)
        ws.cell(dst_row, 2, cc_label)
        ws.cell(dst_row, 3, libc)
        ws.cell(dst_row, 4, seg)
        ws.cell(dst_row, 5, f'=IF(G${base}=0,"",G{src_row}/G${base})')
        ws.cell(dst_row, 6, f'=IF(H${base}=0,"",H{src_row}/H${base})')
        ws.cell(dst_row, 7, f'=IF(OR(E{dst_row}="",E{dst_row}=0,F{dst_row}="",F{dst_row}=0),"",F{dst_row}/E{dst_row})')

    # ---- 说明追加 ----
    note_row = norm_hdr + len(ROWS) + 1
    notes = [
        "扩展段说明（2026-09-16 追加）：",
        "7. 扩展段 21 行：5 个 march 组合（rv32imc / +zcb / +zba_zbb_zbs / +zcmp / +zicond）× GCC/LLVM × newlib-nano/picolibc + 全扩展组合 × newlib × GCC。",
        "8. 体积比/性能比基准 = 原表（无扩展 rv32im_zicsr）同 C 库 GCC -O2（newlib→行7，picolibc→行16）。",
        "9. 扩展段 march 含 rv32imc：Zcb/Zcmp 为 RV32C 子集；Zba/Zbb/Zbs/Zicond 可与 C 叠加。",
        "10. 全扩展 = rv32imc_zcb_zba_zbb_zbs_zcmp_zicond_zicsr，验证 6 个 Z 扩展同时使能。",
    ]
    for n, t in enumerate(notes):
        ws.cell(note_row + n, 1, t)

    try:
        wb.save(XLSX)
        print(f"OK 追加 {len(main_rows)} 行主表 + 归一化 + 说明 -> {XLSX}")
    except PermissionError:
        import time
        alt = os.path.join(os.path.dirname(XLSX),
                           f"BD32_CoreMark_Compiler_Comparison_{time.strftime('%Y%m%d_%H%M%S')}.xlsx")
        wb.save(alt)
        print(f"[WARN] {XLSX} 被占用，结果已写入备用文件 -> {alt}")


if __name__ == "__main__":
    main()
