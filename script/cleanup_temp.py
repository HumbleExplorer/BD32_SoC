#!/usr/bin/env python3
"""
BD32 project temp-file cleaner.

Removes generated / temporary artifacts that are safe to regenerate:
  - ModelSim work libraries:  any */work under the repo (rtl/**, tb/, script/*/, root)
  - ModelSim run files:       transcript, vsim.wlf, vish_stacktrace.vstf,
                              modelsim.ini, wlft*, *.log under script/ and tb/
  - Vivado scattered logs:    vivado*.jou / vivado*.log / vivado_*.backup.* at
                              repo root, BD32_SoC/, script/**, logs/（正式运行
                              日志在 BD32_SoC.runs/<run>/runme.log 不受影响）
  - Vivado temp dirs:         .Xil/ anywhere; BD32_SoC/BD32_SoC.hw（hw_ila 会话）
  - Vivado sim output:        BD32_SoC/BD32_SoC.sim（xsim 行为仿真，--with-sim，
                              默认保留——重跑流程耗时长）
  - Python cache:             __pycache__ dirs and *.pyc (recursive)
  - Test logs:                logs/*  (keep the logs/ directory itself)
  - Build dirs (optional):    build/, build_*/ under the repo (--remove-builds)

Never touches tracked sources (rtl/, tb/*.sv, SDK/ source files, doc/, README.md ...);
BD32_SoC.runs/（含当前比特流）与 BD32_SoC/incremental_file/（增量编译参考）永不触碰。

Usage:
  python script/cleanup_temp.py            # list files, ask [y/N] then delete
  python script/cleanup_temp.py --apply    # delete without asking
  python script/cleanup_temp.py --dry-run  # list only, delete nothing
  python script/cleanup_temp.py --apply --keep-logs
  python script/cleanup_temp.py --apply --remove-builds   # 同时删除 build/、build_* 构建产物目录
  python script/cleanup_temp.py --apply --with-sim        # 同时删除 BD32_SoC.sim（xsim 输出）
"""

import argparse
import os
import shutil

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))  # Working/

SIM_ARTIFACT_NAMES = ("vsim.wlf", "transcript", "vish_stacktrace.vstf")
# 注意：modelsim.ini 已不是可删 artifact——work 库统一迁移后它承载
# work → build/msim/<test>/work 的映射（git 跟踪），误删会让 runner 散落重建。
SIM_ARTIFACT_PREFIXES = ("wlft")
SIM_ARTIFACT_SUFFIXES = (".log", ".wlf")


def is_sim_artifact(name):
    if name in SIM_ARTIFACT_NAMES:
        return True
    if name.startswith(SIM_ARTIFACT_PREFIXES):
        return True
    if name.endswith(SIM_ARTIFACT_SUFFIXES):
        return True
    return False


def is_within(path, root):
    try:
        return os.path.commonpath([os.path.abspath(path), os.path.abspath(root)]) == os.path.abspath(root)
    except ValueError:
        return False


def is_vivado_stray(dirpath, f):
    """Vivado 会话散落日志：vivado*.jou / vivado*.log / vivado_*.backup.*。
    只在根目录、BD32_SoC/、script/**、logs/ 生效；runs/ 内的 runme.log 不在
    遍历范围（collect 不下探 BD32_SoC.runs）。"""
    name = f.lower()
    if not (name.endswith(".jou") or name.endswith(".log")):
        return False
    rel = os.path.relpath(dirpath, REPO)
    scope = rel == "." or rel == "BD32_SoC" or rel.startswith("script") or rel.startswith("logs")
    if not scope:
        return False
    return name.startswith("vivado")


def collect():
    """Return list of (kind, path) to remove."""
    targets = []

    # ModelSim run files (recursive under script/ and tb/)
    for base in ("script", "tb"):
        full = os.path.join(REPO, base)
        if not os.path.isdir(full):
            continue
        for dirpath, dirnames, filenames in os.walk(full):
            if "work" in dirnames:
                dirnames.remove("work")  # work 库由下方单独处理
            for f in filenames:
                if is_sim_artifact(f):
                    targets.append(("artifact", os.path.join(dirpath, f)))

    # work libraries (recursive: rtl/**, tb/, script/*/, repo root)
    # + __pycache__ + .pyc + Vivado 散落日志 + .Xil
    for dirpath, dirnames, filenames in os.walk(REPO):
        # skip .git and vendored toolchains; 永不下探比特流/增量参考/生成目录
        dirnames[:] = [
            d
            for d in dirnames
            if d not in (".git", "third_party", "BD32_SoC.runs",
                         "incremental_file", "build", "BD32_SoC.cache",
                         "BD32_SoC.gen", "ip_user_files")
        ]
        if "work" in dirnames:
            targets.append(("work", os.path.join(dirpath, "work")))
            dirnames.remove("work")  # do not descend into the library itself
        if ".Xil" in dirnames:
            targets.append(("xil", os.path.join(dirpath, ".Xil")))
            dirnames.remove(".Xil")
        if "BD32_SoC.hw" in dirnames:
            targets.append(("hw", os.path.join(dirpath, "BD32_SoC.hw")))
            dirnames.remove("BD32_SoC.hw")
        if "__pycache__" in dirnames:
            targets.append(("pycache", os.path.join(dirpath, "__pycache__")))
        for f in filenames:
            if f.endswith(".pyc"):
                targets.append(("pyc", os.path.join(dirpath, f)))
            elif is_vivado_stray(dirpath, f):
                targets.append(("vivado", os.path.join(dirpath, f)))

    return targets


def main():
    ap = argparse.ArgumentParser(description="BD32 temp-file cleaner")
    ap.add_argument("--apply", action="store_true", help="delete without confirmation prompt")
    ap.add_argument("--dry-run", action="store_true", help="list only, do not delete")
    ap.add_argument("--keep-logs", action="store_true", help="do not clear logs/")
    ap.add_argument("--remove-builds", action="store_true",
                    help="同时删除 build/、build_* 构建产物目录（默认保留）")
    ap.add_argument("--with-sim", action="store_true",
                    help="同时删除 BD32_SoC/BD32_SoC.sim（xsim 行为仿真输出，默认保留）")
    args = ap.parse_args()

    targets = collect()
    if args.with_sim:
        simdir = os.path.join(REPO, "BD32_SoC", "BD32_SoC.sim")
        if os.path.isdir(simdir):
            targets.append(("sim", simdir))
    if not args.keep_logs:
        logdir = os.path.join(REPO, "logs")
        if os.path.isdir(logdir):
            for f in os.listdir(logdir):
                p = os.path.join(logdir, f)
                if os.path.isfile(p):
                    targets.append(("log", p))

    # 可选：构建产物目录（build/、build_O2/、build_clang_* 等；默认不删）
    if args.remove_builds:
        for dirpath, dirnames, filenames in os.walk(REPO):
            dirnames[:] = [d for d in dirnames if d not in (".git", "third_party")]
            for d in list(dirnames):
                if d == "build" or d.startswith("build_"):
                    targets.append(("build", os.path.join(dirpath, d)))
                    dirnames.remove(d)

    # de-dup, keep first occurrence
    seen = set()
    uniq = []
    for kind, p in targets:
        if p not in seen:
            seen.add(p)
            uniq.append((kind, p))
    uniq.sort(key=lambda x: x[1])

    mode = "DRY-RUN" if args.dry_run else ("APPLY" if args.apply else "CONFIRM")
    print("BD32 temp cleaner")
    print("  repo: %s" % REPO)
    print("  mode: %s" % mode)
    print("  targets: %d" % len(uniq))
    for kind, p in uniq:
        rel = os.path.relpath(p, REPO)
        print("    [%s] %s" % (kind, rel))

    if not uniq:
        print("  nothing to clean.")
        return 0

    if args.dry_run:
        print("  (dry run, nothing deleted)")
        return 0

    if not args.apply:
        try:
            ans = input("  Delete %d items? [y/N]: " % len(uniq))
        except EOFError:
            ans = ""
        if ans.strip().lower() not in ("y", "yes"):
            print("  aborted, nothing deleted.")
            return 0

    deleted = 0
    for kind, p in uniq:
        if not is_within(p, REPO):
            print("  [skip] outside repo: %s" % p)
            continue
        try:
            if kind in ("work", "pycache", "build", "xil", "hw", "sim"):
                shutil.rmtree(p, ignore_errors=True)
            else:
                os.remove(p)
            deleted += 1
        except OSError:
            pass
    print("  deleted %d items." % deleted)
    return 0


if __name__ == "__main__":
    main()
