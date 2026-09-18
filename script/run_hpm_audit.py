#!/usr/bin/env python3
"""HPM 审计回归：hpm_audit_test + tb_core_top 参考模型（+define+HPM_AUDIT）。

用法: python script/run_hpm_audit.py
"""
import os
import re
import subprocess
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
CORE_TEST_DIR = os.path.join(SCRIPT_DIR, "..", "script", "core_test")
TEST = "hpm_audit_test"


def find_tool(name):
    for base in (r"D:\modeltech64_2020.4\win64",):
        p = os.path.join(base, name)
        if os.path.exists(p):
            return p
    return name


VLOG = find_tool("vlog.exe")
VSIM = find_tool("vsim.exe")


def main():
    filelist = os.path.join(CORE_TEST_DIR, "filelist.f")
    r = subprocess.run(
        [VLOG, "-f", filelist,
         "+define+DIRECT_LOAD", "+define+CORE_TEST", "+define+CUSTOM_ASM",
         "+define+HPM_AUDIT"],
        cwd=CORE_TEST_DIR, capture_output=True, text=True, timeout=300)
    errs = [l for l in (r.stdout or "").split("\n")
            if re.search(r"\bError\b", l) and "Errors:" not in l and not l.startswith("** Note")]
    if r.returncode != 0 or errs:
        print("COMPILE FAILED")
        for e in errs[:20]:
            print("  [Error]", e)
        sys.exit(1)
    print("compile OK")

    do_cmd = f"run 3ms; quit -f"
    r = subprocess.run(
        [VSIM, "-batch", "-voptargs=+acc", "tb_core_top",
         "-G", f"ITCM_FILE={TEST}.dat", "-do", do_cmd],
        cwd=CORE_TEST_DIR, capture_output=True, text=True, timeout=600)
    out = (r.stdout or "") + (r.stderr or "")

    audit_fail = re.findall(r"\[AUDIT FAIL\].*", out)
    for l in re.findall(r"\[AUDIT (?:PASS|INFO)\].*|==== HPM AUDIT.*|HPM AUDIT:.*", out):
        print(l)
    for l in audit_fail:
        print(l)
    if "HPM AUDIT: ALL PASS" in out and "test passed !!!!!" in out:
        print("RESULT: PASS")
    else:
        print("RESULT: FAIL")
        sys.exit(1)


if __name__ == "__main__":
    main()
