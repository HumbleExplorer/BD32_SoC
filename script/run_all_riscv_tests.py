#!/usr/bin/env python3
"""
BD32 RISC-V CPU 批量测试运行脚本
遍历 test_data/riscv-tests 下所有 rv32*.dat，通过 ModelSim core_test 跑仿真，输出 PASS/FAIL 汇总。

DTCM 数据说明：
  tb_core_top.sv 中已设置 .DTCM_FILE(ITCM_FILE)，即 DTCM 加载与 ITCM 相同的 .dat 文件。
  riscv-tests 的 .dat 文件中，地址偏移 0x1000 之后为数据段。
  $readmemh 按字地址顺序填充 DTCM 的 ram_mem，所以 CPU load 访问 0x0001_1000 时，
  ram_mem[1024] 即为 .dat 文件第 1024 行的数据，天然正确。

用法：
  cd Working/script
  python run_all_riscv_tests.py

依赖：
  - ModelSim SE-64 2020.4 (vsim 需在 PATH 或通过 VSIM_PATH 指定)
"""

import os
import sys
import subprocess
import re
import glob
import time
import shutil

# ANSI 颜色支持检测
_USE_COLOR = True
if os.name == "nt":
    if not os.environ.get("TERM") and not os.environ.get("WT_SESSION"):
        try:
            import ctypes
            kernel32 = ctypes.windll.kernel32
            hStdout = kernel32.GetStdHandle(-11)
            mode = ctypes.c_uint32()
            kernel32.GetConsoleMode(hStdout, ctypes.byref(mode))
            kernel32.SetConsoleMode(hStdout, mode.value | 0x0004)
            _USE_COLOR = True
        except Exception:
            _USE_COLOR = False

# ============================================================
# 配置
# ============================================================

# ModelSim 路径（None 表示自动在 PATH 查找）
VSIM_PATH = r"D:\modeltech64_2020.4\win64"

# 工作目录
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
CORE_TEST_DIR = os.path.join(BASE_DIR, "core_test")
TEST_DATA_DIR = os.path.abspath(os.path.join(BASE_DIR, "..", "test_data/riscv-tests"))

# 仿真运行时长（微秒）& 超时（秒）
SIM_TIME_US = 50
TIMEOUT_SEC = 60

# ============================================================
# 工具函数
# ============================================================

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
        vsim = os.path.join(VSIM_PATH, "vsim")
        if os.path.exists(vsim):
            return vsim
        vsim_exe = os.path.join(VSIM_PATH, "vsim.exe")
        if os.path.exists(vsim_exe):
            return vsim_exe
    for path_dir in os.environ.get("PATH", "").split(os.pathsep):
        vsim = os.path.join(path_dir, "vsim")
        if os.path.exists(vsim):
            return vsim
        vsim_exe = os.path.join(path_dir, "vsim.exe")
        if os.path.exists(vsim_exe):
            return vsim_exe
    default_paths = [
        r"D:\modeltech64_2020.4\win64\vsim.exe",
        r"C:\modeltech64_2020.4\win64\vsim.exe",
    ]
    for p in default_paths:
        if os.path.exists(p):
            return p
    return None


def find_vlog():
    vsim_path = find_vsim()
    if vsim_path:
        vlog_path = os.path.join(os.path.dirname(vsim_path), "vlog")
        if os.path.exists(vlog_path):
            return vlog_path
        vlog_path_exe = os.path.join(os.path.dirname(vsim_path), "vlog.exe")
        if os.path.exists(vlog_path_exe):
            return vlog_path_exe
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
    """一次编译所有 RTL（带 +define+CORE_TEST）"""
    print("=" * 60)
    print("  Step 1: Compiling RTL with +define+CORE_TEST ...")
    print("=" * 60)

    filelist = os.path.join(CORE_TEST_DIR, "filelist.f")
    if not os.path.exists(filelist):
        print(f"[ERROR] filelist.f not found: {filelist}")
        return False

    cmd = [vlog_exe, "-f", filelist, "+define+CORE_TEST"]

    try:
        result = subprocess.run(cmd, cwd=CORE_TEST_DIR, capture_output=True,
                                text=True, timeout=120)
        errors = [l for l in result.stdout.split("\n")
                  if "Error" in l and not l.startswith("** Note")]
        warnings = [l for l in result.stdout.split("\n") if "Warning" in l]

        for e in errors[:10]:
            print(f"  [Error] {e}")
        for w in warnings[:10]:
            print(f"  [Warning] {w}")

        if result.returncode != 0:
            print(f"\n  [FAIL] Compilation failed (rc={result.returncode})")
            return False
        print(f"  [OK] Compilation successful (Errors: 0, Warnings: {len(warnings)})")
        return True
    except subprocess.TimeoutExpired:
        print("  [FAIL] Compilation timed out (120s)")
        return False
    except Exception as e:
        print(f"  [FAIL] Compilation error: {e}")
        return False


def run_single_test(vsim_exe, test_name, sim_time_us=SIM_TIME_US, timeout=TIMEOUT_SEC):
    """
    运行单个测试。
    DTCM_FILE 由 tb_core_top.sv 内部硬连线为 ITCM_FILE（.DTCM_FILE(ITCM_FILE)），
    因此 DTCM 自动加载与 ITCM 相同的 .dat 文件，数据段天然存在。
    """
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
            m = re.search(r"test\[(\d+)\]", output)
            detail = f"test[{m.group(1)}]" if m else "unknown"
            return ("FAIL", detail)
        else:
            if "Fatal" in output or "Error" in output:
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
    pattern = os.path.join(TEST_DATA_DIR, "rv32*.dat")
    files = sorted(glob.glob(pattern))
    test_list = []
    for f in files:
        basename = os.path.basename(f)
        if basename.startswith("rv32ui-p-") or basename.startswith("rv32um-p-"):
            test_list.append(basename)
    return test_list


def check_license(vsim_exe):
    try:
        result = subprocess.run(
            [vsim_exe, "-c", "-do", "quit -f", "tb_core_top"],
            cwd=CORE_TEST_DIR, capture_output=True, text=True, timeout=15)
        output = result.stdout + result.stderr
        if "Invalid license" in output or "Unable to checkout" in output:
            return False, "License checkout failed. Check LM_LICENSE_FILE."
        return True, ""
    except subprocess.TimeoutExpired:
        return False, "vsim timed out"
    except Exception as e:
        return False, str(e)


def print_summary(results, elapsed):
    passed = sum(1 for r in results if r[1] == "PASS")
    failed = sum(1 for r in results if r[1] == "FAIL")
    crashed = sum(1 for r in results if r[1] == "CRASH")
    timeout = sum(1 for r in results if r[1] == "TIMEOUT")
    total = len(results)

    print()
    print("=" * 60)
    print("  RISC-V Tests Summary")
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
    if passed:
        parts.append(GREEN(f"Passed:  {passed}"))
    if failed:
        parts.append(RED(f"Failed:  {failed}"))
    if crashed:
        parts.append(PURPLE(f"Crashed: {crashed}"))
    if timeout:
        parts.append(YELLOW(f"Timeout: {timeout}"))
    print(f"  {' | '.join(parts)}")
    print(f"  Total:   {total}  (elapsed: {elapsed:.1f}s)")
    print("=" * 60)


# ============================================================
# 主函数
# ============================================================

def main():
    start_time = time.time()

    print()
    print("╔" + "═" * 58 + "╗")
    print("║  BD32 RISC-V CPU — 批量测试运行器                    ║")
    print("╚" + "═" * 58 + "╝")
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
    print(f"  work dir: {CORE_TEST_DIR}")
    print(f"  test data: {TEST_DATA_DIR}")
    print()

    # 获取测试列表
    test_list = get_test_list()
    if not test_list:
        print(f"[ERROR] No rv32*.dat test files found in {TEST_DATA_DIR}")
        sys.exit(1)
    print(f"  Found {len(test_list)} test files")
    print()

    # 检查 license
    print("  Checking vsim license ...", end=" ", flush=True)
    lic_ok, lic_msg = check_license(vsim_exe)
    if not lic_ok:
        print(f"{RED('FAIL')}")
        print(f"  {lic_msg}")
        sys.exit(1)
    print(f"{GREEN('OK')}")
    print()

    # 编译
    clean_work_dir()
    if not compile_design(vlog_exe):
        sys.exit(1)

    # 逐个运行测试
    print()
    print("=" * 60)
    print(f"  Step 2: Running {len(test_list)} tests (sim_time={SIM_TIME_US}us, timeout={TIMEOUT_SEC}s)")
    print(f"  Note: DTCM auto-loads the same .dat as ITCM (data at offset 0x1000)")
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
