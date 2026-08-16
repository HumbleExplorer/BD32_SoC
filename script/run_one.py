#!/usr/bin/env python3
"""聚焦运行单个 custom_asm 测试：编译 RTL 一次，然后只跑指定测试。
用法: python run_one.py m_extension_stress
"""
import os, sys, subprocess, shutil, re

VSIM_PATH = os.environ.get("MODELSIM_PATH", r"D:\modeltech64_2020.4\win64")
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
CORE_TEST_DIR = os.path.join(BASE_DIR, "core_test")
SIM_TIME_US = 1000

def main():
    test = sys.argv[1] if len(sys.argv) > 1 else "m_extension_stress"
    vlog = os.path.join(VSIM_PATH, "vlog.exe")
    vsim = os.path.join(VSIM_PATH, "vsim.exe")

    # clean (tolerate locked files, e.g. ModelSim GUI holding the library)
    work = os.path.join(CORE_TEST_DIR, "work")
    if os.path.exists(work):
        shutil.rmtree(work, ignore_errors=True)
        if os.path.exists(work):
            print("  [warn] work dir partially locked, continuing anyway")
    for f in ["vsim.wlf", "transcript", "vish_stacktrace.vstf"]:
        fp = os.path.join(CORE_TEST_DIR, f)
        try:
            if os.path.exists(fp):
                os.remove(fp)
        except OSError:
            pass

    # compile
    print("=== Compiling RTL ===")
    filelist = os.path.join(CORE_TEST_DIR, "filelist.f")
    r = subprocess.run([vlog, "-f", filelist,
                        "+define+DIRECT_LOAD", "+define+CORE_TEST", "+define+CUSTOM_ASM"],
                       cwd=CORE_TEST_DIR, capture_output=True, text=True, timeout=180)
    errs = [l for l in r.stdout.split("\n") if "Error" in l and not l.startswith("** Note")]
    for e in errs[:20]:
        print("  [Error]", e)
    if r.returncode != 0:
        print("COMPILE FAILED rc=", r.returncode)
        print(r.stdout[-2000:])
        sys.exit(1)
    print("  compile OK")

    # run
    print(f"=== Running {test} ===")
    do_cmd = f"run {SIM_TIME_US}us; quit -f"
    r = subprocess.run([vsim, "-batch", "-voptargs=+acc", "tb_core_top",
                        "-G", f"ITCM_FILE={test}.dat", "-do", do_cmd],
                       cwd=CORE_TEST_DIR, capture_output=True, text=True, timeout=180)
    out = r.stdout + r.stderr
    if "test passed !!!!!" in out:
        print("RESULT: PASS")
    elif "test failed !!!!!" in out:
        matches = re.findall(r"test\[\s*(\d+)\]", out)
        print("RESULT: FAIL sub=", matches[-1] if matches else "unknown")
    else:
        print("RESULT: TIMEOUT/CRASH")
    # print tail for diagnostics
    print("---- transcript tail ----")
    print(out[-1500:])

if __name__ == "__main__":
    main()
