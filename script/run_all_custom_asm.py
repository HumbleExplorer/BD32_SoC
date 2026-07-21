#!/usr/bin/env python3
"""
BD32 RISC-V CPU — 自定义汇编测试批量运行脚本
遍历 test_data/custom_asm 下所有 *.dat，通过 ModelSim core_test 跑仿真，输出 PASS/FAIL 汇总。

编译时使用 +define+DIRECT_LOAD +define+CORE_TEST +define+CUSTOM_ASM，
使 SoC_Config.sv 中 PATH 指向 test_data/custom_asm/。

用法：
  cd Working/script
  python run_all_custom_asm.py

依赖：
  - ModelSim SE-64 2020.4 (vsim 需在 VSIM_PATH 指定)
"""

import os
import sys
import subprocess
import re
import glob
import time
import shutil

# ============================================================
# 配置
# ============================================================

VSIM_PATH = r"D:\modeltech64_2020.4\win64"

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
CORE_TEST_DIR = os.path.join(BASE_DIR, "core_test")
TEST_DATA_DIR = os.path.abspath(os.path.join(BASE_DIR, "..", "test_data", "custom_asm"))

SIM_TIME_US = 1000
TIMEOUT_SEC = 60

# ============================================================
# 工具函数
# ============================================================

_USE_COLOR = True
if os.name == "nt":
    if not os.environ.get("TERM") and not os.environ.get("WT_SESSION"):
        try:
            import ctypes
            kernel32 = ctypes.windll.kernel32
            hStdout = kernel32.GetConsoleHandle(-11)
            mode = ctypes.c_uint32()
            kernel32.GetConsoleMode(hStdout, ctypes.byref(mode))
            kernel32.SetConsoleMode(hStdout, mode.value | 0x0004)
        except Exception:
            _USE_COLOR = False


def color(text, code):
    if _USE_COLOR:
        return f"\033[{code}m{text}\033[0m"
    return text

GREEN  = lambda t: color(t, "92")
RED    = lambda t: color(t, "91")
PURPLE = lambda t: color(t, "95")
YELLOW = lambda t: color(t, "93")


def find_vsim():
    if VSIM_PATH:
        for name in ["vsim.exe", "vsim"]:
            p = os.path.join(VSIM_PATH, name)
            if os.path.exists(p):
                return p
    return None


def find_vlog():
    vsim = find_vsim()
    if vsim:
        d = os.path.dirname(vsim)
        for name in ["vlog.exe", "vlog"]:
            p = os.path.join(d, name)
            if os.path.exists(p):
                return p
    return None


def clean_work_dir():
    work_dir = os.path.join(CORE_TEST_DIR, "work")
    if os.path.exists(work_dir):
        shutil.rmtree(work_dir)
    for f in ["vsim.wlf", "transcript", "vish_stacktrace.vstf"]:
        fp = os.path.join(CORE_TEST_DIR, f)
        if os.path.exists(fp):
            os.remove(fp)


def compile_design(vlog_exe):
    print("=" * 60)
    print("  Step 1: Compiling RTL (+DIRECT_LOAD +CORE_TEST +CUSTOM_ASM)")
    print("=" * 60)

    filelist = os.path.join(CORE_TEST_DIR, "filelist.f")
    if not os.path.exists(filelist):
        print(f"  [ERROR] filelist.f not found: {filelist}")
        return False

    cmd = [vlog_exe, "-f", filelist,
           "+define+DIRECT_LOAD", "+define+CORE_TEST", "+define+CUSTOM_ASM"]

    try:
        result = subprocess.run(cmd, cwd=CORE_TEST_DIR, capture_output=True,
                                text=True, timeout=120)
        errors = [l for l in result.stdout.split("\n")
                  if "Error" in l and not l.startswith("** Note")]
        warnings = [l for l in result.stdout.split("\n") if "Warning" in l]

        for e in errors[:10]:
            print(f"  [Error] {e}")
        if result.returncode != 0:
            print(f"\n  [FAIL] Compilation failed (rc={result.returncode})")
            return False
        print(f"  [OK] Compilation successful (Errors: 0, Warnings: {len(warnings)})")
        return True
    except subprocess.TimeoutExpired:
        print("  [FAIL] Compilation timed out (120s)")
        return False


def run_single_test(vsim_exe, test_name, sim_time_us=SIM_TIME_US, timeout=TIMEOUT_SEC):
    do_cmd = f"run {sim_time_us}us; quit -f"
    cmd = [
        vsim_exe, "-c", "-voptargs=+acc", "tb_core_top",
        "-G", f"ITCM_FILE={test_name}",
        "-do", do_cmd,
    ]

    try:
        result = subprocess.run(cmd, cwd=CORE_TEST_DIR, capture_output=True,
                                text=True, timeout=timeout)
        output = result.stdout + result.stderr

        if "test passed !!!!!" in output:
            return ("PASS", "")
        elif "test failed !!!!!" in output:
            # 提取最大的 test[N] 编号（即失败的子测试）
            matches = re.findall(r"test\[\s*(\d+)\]", output)
            detail = f"sub={matches[-1]}" if matches else "unknown"
            return ("FAIL", detail)
        else:
            # 只匹配 ModelSim 真正的错误行（** Error: / ** Fatal:），排除版权信息
            has_real_error = any("** Error" in line or "** Fatal" in line
                                 for line in output.split("\n"))
            if has_real_error:
                return ("CRASH", output[-200:].strip())
            elif result.returncode != 0:
                return ("CRASH", f"exit code {result.returncode}")
            else:
                return ("TIMEOUT", "no pass/fail detected")
    except subprocess.TimeoutExpired:
        return ("TIMEOUT", f">{timeout}s")
    except Exception as e:
        return ("ERROR", str(e))


def get_test_list():
    pattern = os.path.join(TEST_DATA_DIR, "*.dat")
    files = sorted(glob.glob(pattern))
    return [os.path.basename(f) for f in files]


def print_summary(results, elapsed):
    passed = sum(1 for r in results if r[1] == "PASS")
    failed = sum(1 for r in results if r[1] == "FAIL")
    crashed = sum(1 for r in results if r[1] == "CRASH")
    timeout = sum(1 for r in results if r[1] in ("TIMEOUT", "ERROR"))
    total = len(results)

    print()
    print("=" * 60)
    print("  Custom ASM Tests Summary")
    print("=" * 60)
    print(f"  {'Test Name':<30} {'Result':<10} {'Detail'}")
    print("  " + "-" * 55)
    for name, status, detail in results:
        ns = name.replace(".dat", "")
        if status == "PASS":
            print(f"  {ns:<30} {GREEN(status):<10} {detail}")
        elif status == "FAIL":
            print(f"  {ns:<30} {RED(status):<10} {detail}")
        elif status == "CRASH":
            print(f"  {ns:<30} {PURPLE(status):<10} {detail}")
        else:
            print(f"  {ns:<30} {YELLOW(status):<10} {detail}")
    print("  " + "-" * 55)

    parts = []
    if passed:  parts.append(GREEN(f"Passed:  {passed}"))
    if failed:  parts.append(RED(f"Failed:  {failed}"))
    if crashed: parts.append(PURPLE(f"Crashed: {crashed}"))
    if timeout: parts.append(YELLOW(f"Timeout: {timeout}"))
    print(f"  {' | '.join(parts)}")
    print(f"  Total:   {total}  (elapsed: {elapsed:.1f}s)")
    print("=" * 60)


# ============================================================
# 主函数
# ============================================================

def main():
    start_time = time.time()

    print()
    print("=" * 60)
    print("  BD32 RISC-V CPU — 自定义汇编测试批量运行器")
    print("=" * 60)
    print()

    vsim_exe = find_vsim()
    vlog_exe = find_vlog()

    if not vsim_exe:
        print("[ERROR] vsim not found.")
        sys.exit(1)
    if not vlog_exe:
        print("[ERROR] vlog not found.")
        sys.exit(1)

    print(f"  vsim: {vsim_exe}")
    print(f"  vlog: {vlog_exe}")
    print(f"  work dir:  {CORE_TEST_DIR}")
    print(f"  test data: {TEST_DATA_DIR}")
    print()

    test_list = get_test_list()
    if not test_list:
        print(f"[ERROR] No .dat files found in {TEST_DATA_DIR}")
        sys.exit(1)
    print(f"  Found {len(test_list)} custom asm tests")
    print()

    clean_work_dir()
    if not compile_design(vlog_exe):
        sys.exit(1)

    print()
    print("=" * 60)
    print(f"  Step 2: Running {len(test_list)} tests "
          f"(sim_time={SIM_TIME_US}us, timeout={TIMEOUT_SEC}s)")
    print("=" * 60)
    print()

    results = []
    for i, test_name in enumerate(test_list, 1):
        ns = test_name.replace(".dat", "")
        print(f"  [{i:2d}/{len(test_list)}] {ns} ...", end=" ", flush=True)

        ts = time.time()
        status, detail = run_single_test(vsim_exe, test_name)
        te = time.time() - ts

        if status == "PASS":
            print(f"{GREEN('PASS')} ({te:.1f}s)")
        elif status == "FAIL":
            print(f"{RED('FAIL')} ({detail}, {te:.1f}s)")
        elif status == "CRASH":
            print(f"{PURPLE('CRASH')} ({detail}, {te:.1f}s)")
        else:
            print(f"{YELLOW(status)} ({detail}, {te:.1f}s)")

        results.append((test_name, status, detail))

    elapsed = time.time() - start_time
    print_summary(results, elapsed)

    failed_tests = [r for r in results if r[1] != "PASS"]
    if failed_tests:
        print()
        print("  Non-passing tests:")
        for name, status, detail in failed_tests:
            print(f"    - {name}: {status} ({detail})")

    return 0 if all(r[1] == "PASS" for r in results) else 1


if __name__ == "__main__":
    sys.exit(main())
