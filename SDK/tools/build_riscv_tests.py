"""
编译 riscv-tests（rv32ui + rv32um）到 test_data/riscv-tests/

工作目录为 SDK/isa：
  - env/ 使用仓库内维护的 BD32 文件（link.ld / riscv_test.h / encoding.h）；
  - rv32ui / rv32um / rv64ui / macros 若缺失，自动从 third_party/riscv-tests/isa
    复制补齐（第三方源码位置可用环境变量 RISCV_TESTS_SRC 覆盖）。

BD32 内存布局：ITCM @ 0x00010000, DTCM @ 0x00020000
"""
import subprocess, os, struct, sys
from isa_env import ensure_sdk_isa

# ===== 路径 =====
REPO_ROOT   = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
RISCV_TESTS = os.environ.get("RISCV_TESTS_SRC", os.path.join(REPO_ROOT, "third_party", "riscv-tests"))
SDK_ISA     = os.path.join(REPO_ROOT, "SDK", "isa")
ISA_SRC     = SDK_ISA
ENV_P       = os.path.join(SDK_ISA, "env", "p")
OUT_DIR     = os.path.join(REPO_ROOT, "test_data", "riscv-tests")
LD_SCRIPT   = os.path.join(ENV_P, "link.ld")

_TC = os.environ.get("RISCV_TOOLCHAIN", r"D:/RISCV_Tool/xpack-riscv-none-elf-gcc-15.2.0-1/bin")
CC      = os.path.join(_TC, "riscv-none-elf-gcc")
OBJCOPY = os.path.join(_TC, "riscv-none-elf-objcopy")
OBJDUMP = os.path.join(_TC, "riscv-none-elf-objdump")

# 官方 LLVM / Clang (--clang 时用于汇编 riscv-tests 的 .S，链接仍用 xpack gcc)
LLVM_BIN = os.environ.get("LLVM_BIN", r"D:/RISCV_Tool/llvm-22.1.8/bin")
CLANG    = os.path.join(LLVM_BIN, "clang")
# 命令行带 --clang 时启用 LLVM 汇编；否则完全保持原有 gcc 行为
USE_CLANG = "--clang" in sys.argv

# ===== BD32 riscv-tests link.ld（指令 @ 0x10000, 数据 @ 0x11000）=====
LD_CONTENT = """OUTPUT_ARCH("riscv")
ENTRY(_start)

SECTIONS
{
  . = 0x00010000;
  .text.init : { *(.text.init) }

  . = 0x00011000;
  .tohost :   { *(.tohost) }
  .data :     { *(.data) }
  .bss :      { *(.bss) }
  _end = .;
}
"""

# ===== 准备 SDK/isa 工作目录 =====
ensure_sdk_isa(REPO_ROOT, RISCV_TESTS)
os.makedirs(ENV_P, exist_ok=True)

with open(LD_SCRIPT, "w") as f:
    f.write(LD_CONTENT)

print("  [link.ld: 指令 @ 0x10000 / 数据 @ 0x11000]")

# ===== 编译选项 =====
CFLAGS = [
    "-march=rv32im_zicsr_zifencei", "-mabi=ilp32",
    "-static", "-mcmodel=medlow",
    "-nostdlib", "-nostartfiles", "-ffreestanding",
    "-I", ENV_P,
    "-I", os.path.join(ISA_SRC, "macros", "scalar"),
]
LDFLAGS = [
    "-T", LD_SCRIPT,
    "-lgcc",
]

# ===== 生成 .dat（flat binary，保留地址空间正确 padding）=====
def make_dat(elf_path, dat_path):
    tmp_bin = elf_path + ".tmp.bin"
    try:
        subprocess.run([OBJCOPY, "-O", "binary", elf_path, tmp_bin],
                       capture_output=True, check=True)
        with open(tmp_bin, "rb") as f:
            data = f.read()
        if len(data) % 4:
            data += b'\x00' * (4 - len(data) % 4)
        with open(dat_path, "w") as f:
            for i in range(0, len(data), 4):
                word = struct.unpack_from("<I", data, i)[0]
                f.write(f"{word:08x}\n")
        print(f"  DAT: {dat_path} ({len(data)//4} words, base=0x10000)")
    finally:
        try:
            os.remove(tmp_bin)
        except:
            pass

# ===== 编译一个测试 =====
def compile_test(test_name, src_file, useclang=False):
    os.makedirs(OUT_DIR, exist_ok=True)
    base = os.path.join(OUT_DIR, test_name)
    elf  = base + ".elf"
    dump = base + ".dump"
    dat  = base + ".dat"
    obj = base + ".o"

    print(f"\n--- {test_name} ---")

    if useclang:
        # clang 汇编 .S → .o (RISC-V 代码生成, 集成汇编器)
        cmd = [CLANG, "--target=riscv32-unknown-elf"] + CFLAGS + ["-c", src_file, "-o", obj]
        r = subprocess.run(cmd, capture_output=True, text=True)
        if r.returncode != 0:
            print(f"  FAIL (clang asm):\n{r.stderr}")
            return False
        # xpack gcc 链接 .o → elf (复用 libgcc + BD32 link.ld)
        cmd = [CC] + CFLAGS + ["-T", LD_SCRIPT, obj, "-lgcc", "-o", elf]
        r = subprocess.run(cmd, capture_output=True, text=True)
        if r.returncode != 0:
            print(f"  FAIL (gcc link):\n{r.stderr}")
            return False
    else:
        # 默认: gcc 一步编译+链接
        cmd = [CC] + CFLAGS + LDFLAGS + ["-o", elf, src_file]
        r = subprocess.run(cmd, capture_output=True, text=True)
        if r.returncode != 0:
            print(f"  FAIL:\n{r.stderr}")
            return False

    # objdump
    dump_out = subprocess.run([OBJDUMP, "-d", elf], capture_output=True, text=True)
    with open(dump, "w") as f:
        f.write(dump_out.stdout)
    print(f"  DMP: {dump}")

    # flat binary dump → .dat
    make_dat(elf, dat)
    return True

# ===== 主流程 =====
tests = []
ui_tests = [
    "simple", "add", "addi", "and", "andi", "auipc",
    "beq", "bge", "bgeu", "blt", "bltu", "bne",
    "fence_i", "jal", "jalr",
    "lb", "lbu", "lh", "lhu", "lui", "lw", "ld_st",
    "or", "ori",
    "sb", "sh", "sw", "st_ld",
    "sll", "slli", "slt", "slti", "sltiu", "sltu",
    "sra", "srai", "srl", "srli", "sub", "xor", "xori",
    "ma_data",
]
for t in ui_tests:
    tests.append(("rv32ui-p-" + t, os.path.join(ISA_SRC, "rv32ui", t + ".S")))

um_tests = ["div", "divu", "mul", "mulh", "mulhsu", "mulhu", "rem", "remu"]
for t in um_tests:
    tests.append(("rv32um-p-" + t, os.path.join(ISA_SRC, "rv32um", t + ".S")))

ok, fail = 0, 0
for name, src in tests:
    if compile_test(name, src, useclang=USE_CLANG):
        ok += 1
    else:
        fail += 1

print(f"\n{'='*50}")
print(f"完成: {ok} 通过, {fail} 失败, 共 {ok+fail} 个测试")
print(f"输出目录: {OUT_DIR}")
