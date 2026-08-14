"""
build_asm.py — 构建自定义汇编测试 (custom_asm)

与 build_asm.sh 功能完全一致，Windows 下直接用 Python 运行，无需 Git Bash / cygpath。

用法：
    python build_asm.py m_extension_stress     # 构建单个
    python build_asm.py all                    # 构建目录下所有 *.S
    python build_asm.py -h                     # 帮助

产物（与 .S 同目录）：
    <name>.elf   链接后的 ELF
    <name>.dump  objdump 反汇编
    <name>.dat   $readmemh 用的字流
"""
import subprocess, sys, os, glob

TOOLCHAIN = os.environ.get("RISCV_TOOLCHAIN", r"D:\RISCV_Tool\xpack-riscv-none-elf-gcc-15.2.0-1\bin")
GCC     = os.path.join(TOOLCHAIN, "riscv-none-elf-gcc.exe")
OBJDUMP = os.path.join(TOOLCHAIN, "riscv-none-elf-objdump.exe")
OBJCOPY = os.path.join(TOOLCHAIN, "riscv-none-elf-objcopy.exe")

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT  = os.path.abspath(os.path.join(SCRIPT_DIR, "..", ".."))

sys.path.insert(0, os.path.join(REPO_ROOT, "SDK", "tools"))
from isa_env import ensure_sdk_isa
ensure_sdk_isa(REPO_ROOT, os.environ.get("RISCV_TESTS_SRC"))

LINK = os.path.join(REPO_ROOT, "SDK", "isa", "env", "p", "link.ld")
INC1 = os.path.join(REPO_ROOT, "SDK", "isa", "env", "p")
INC2 = os.path.join(REPO_ROOT, "SDK", "isa", "macros", "scalar")


def build_one(name):
    s_file = os.path.join(SCRIPT_DIR, f"{name}.S")
    if not os.path.isfile(s_file):
        print(f"ERROR: {name}.S not found")
        return False

    elf = os.path.join(SCRIPT_DIR, f"{name}.elf")
    dump = os.path.join(SCRIPT_DIR, f"{name}.dump")
    bin_ = os.path.join(SCRIPT_DIR, f"{name}.bin")
    dat = os.path.join(SCRIPT_DIR, f"{name}.dat")

    print(f"=== build_asm: {name} ===")

    # 1) 汇编 + 链接
    cmd_gcc = [
        GCC, "-march=rv32im", "-mabi=ilp32", "-O0",
        "-mno-relax", "-Wl,--no-relax",
        "-T", LINK, "-I", INC1, "-I", INC2,
        "-nostdlib", "-static", "-o", elf, s_file
    ]
    r = subprocess.run(cmd_gcc, capture_output=True, text=True)
    if r.returncode != 0:
        print(r.stderr)
        return False

    # 2) 反汇编
    with open(dump, "w", encoding="utf-8") as f:
        subprocess.run([OBJDUMP, "-dS", elf], stdout=f)

    # 3) ELF -> 纯二进制
    subprocess.run([OBJCOPY, "-O", "binary", elf, bin_], check=True)

    # 4) 二进制 -> .dat
    data = open(bin_, "rb").read()
    if len(data) % 4:
        data += b'\x00' * (4 - len(data) % 4)
    with open(dat, "w") as f:
        for i in range(0, len(data), 4):
            f.write("%08x\n" % int.from_bytes(data[i:i+4], "little"))

    os.remove(bin_)
    print(f"  DAT: {len(data)//4} words -> {name}.dat")
    print(f"  OK: {name}.elf / {name}.dump / {name}.dat")
    return True


def main():
    if len(sys.argv) < 2 or sys.argv[1] in ("-h", "--help"):
        print(__doc__)
        return

    os.chdir(SCRIPT_DIR)

    if sys.argv[1] == "all":
        files = sorted(glob.glob(os.path.join(SCRIPT_DIR, "*.S")))
        if not files:
            print("ERROR: no *.S found")
            sys.exit(1)
        ok = True
        for f in files:
            name = os.path.splitext(os.path.basename(f))[0]
            if not build_one(name):
                ok = False
        sys.exit(0 if ok else 1)
    else:
        if not build_one(sys.argv[1]):
            sys.exit(1)


if __name__ == "__main__":
    main()
