#!/usr/bin/env python3
"""
BD32 project temp-file cleaner.

Removes generated / temporary artifacts that are safe to regenerate:
  - ModelSim work libraries:  script/*/work, sim/work, <repo>/work
  - ModelSim run files:        vsim.wlf, transcript, vish_stacktrace.vstf,
                               modelsim.ini under script/*/ and sim/
  - Python cache:              __pycache__ dirs and *.pyc (recursive)
  - Test logs:                 logs/*  (keep the logs/ directory itself)

Never touches tracked sources (rtl/, sim/*.sv, SDK/, doc/, README.md ...).

Usage:
  python script/cleanup_temp.py            # dry run (only lists)
  python script/cleanup_temp.py --apply    # actually delete
  python script/cleanup_temp.py --apply --keep-logs
"""

import argparse
import os
import shutil

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))  # Working/

SIM_ARTIFACTS = ("vsim.wlf", "transcript", "vish_stacktrace.vstf", "modelsim.ini")


def is_within(path, root):
    try:
        return os.path.commonpath([os.path.abspath(path), os.path.abspath(root)]) == os.path.abspath(root)
    except ValueError:
        return False


def collect():
    """Return list of (kind, path) to remove."""
    targets = []

    # work libraries under script/*/, sim/ and the repo root
    for base in ("script", "sim"):
        full = os.path.join(REPO, base)
        if not os.path.isdir(full):
            continue
        for sub in os.listdir(full):
            d = os.path.join(full, sub)
            if os.path.isdir(d):
                work = os.path.join(d, "work")
                if os.path.isdir(work) and is_within(work, REPO):
                    targets.append(("work", work))
                for f in SIM_ARTIFACTS:
                    p = os.path.join(d, f)
                    if os.path.isfile(p):
                        targets.append(("artifact", p))
    root_work = os.path.join(REPO, "work")
    if os.path.isdir(root_work):
        targets.append(("work", root_work))
    sim_wlf = os.path.join(REPO, "sim", "vsim.wlf")
    if os.path.isfile(sim_wlf):
        targets.append(("artifact", sim_wlf))

    # __pycache__ + .pyc (recursive)
    for dirpath, dirnames, filenames in os.walk(REPO):
        # skip .git and vendored toolchains
        dirnames[:] = [
            d
            for d in dirnames
            if d not in (".git", "xpack-openocd-0.12.0-7", "picolibc_install")
        ]
        if "__pycache__" in dirnames:
            targets.append(("pycache", os.path.join(dirpath, "__pycache__")))
        for f in filenames:
            if f.endswith(".pyc"):
                targets.append(("pyc", os.path.join(dirpath, f)))

    return targets


def main():
    ap = argparse.ArgumentParser(description="BD32 temp-file cleaner")
    ap.add_argument("--apply", action="store_true", help="actually delete (default: dry run)")
    ap.add_argument("--keep-logs", action="store_true", help="do not clear logs/")
    args = ap.parse_args()

    targets = collect()
    if not args.keep_logs:
        logdir = os.path.join(REPO, "logs")
        if os.path.isdir(logdir):
            for f in os.listdir(logdir):
                p = os.path.join(logdir, f)
                if os.path.isfile(p):
                    targets.append(("log", p))

    # de-dup, keep first occurrence
    seen = set()
    uniq = []
    for kind, p in targets:
        if p not in seen:
            seen.add(p)
            uniq.append((kind, p))
    uniq.sort(key=lambda x: x[1])

    print("BD32 temp cleaner")
    print("  repo: %s" % REPO)
    print("  mode: %s" % ("APPLY" if args.apply else "DRY-RUN"))
    print("  targets: %d" % len(uniq))
    for kind, p in uniq:
        rel = os.path.relpath(p, REPO)
        print("    [%s] %s" % (kind, rel))

    if args.apply:
        for kind, p in uniq:
            if kind in ("work", "pycache"):
                shutil.rmtree(p, ignore_errors=True)
            else:
                try:
                    os.remove(p)
                except OSError:
                    pass
        print("done.")


if __name__ == "__main__":
    main()
