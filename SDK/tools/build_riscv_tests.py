"""
编译 riscv-tests（rv32ui + rv32um）到 Working/test_data/riscv-tests/
BD32 内存布局：ITCM @ 0x00010000, DTCM @ 0x00020000
"""
import subprocess, os, shutil, struct, re, sys

# ===== 路径 =====
RISCV_TESTS = r"D:\Desktop\毕业设计\参考资料和工具\RISC-V软件\riscv-tests"
ISA_SRC     = os.path.join(RISCV_TESTS, "isa")
ENV_P       = os.path.join(RISCV_TESTS, "env", "p")
TINY_ENV    = r"D:\Desktop\OpenClaw_Workspace\Ref\tinyriscv-master\tests\isa"
OUT_DIR     = r"D:\Desktop\OpenClaw_Workspace\Working\test_data\riscv-tests"
LD_SCRIPT   = os.path.join(ENV_P, "link.ld")

CC      = r"D:/RISCV_Tool/xpack-riscv-none-elf-gcc-15.2.0-1/bin/riscv-none-elf-gcc"
OBJCOPY = r"D:/RISCV_Tool/xpack-riscv-none-elf-gcc-15.2.0-1/bin/riscv-none-elf-objcopy"
OBJDUMP = r"D:/RISCV_Tool/xpack-riscv-none-elf-gcc-15.2.0-1/bin/riscv-none-elf-objdump"

# 官方 LLVM / Clang (--clang 时用于汇编 riscv-tests 的 .S，链接仍用 xpack gcc)
LLVM_BIN = r"D:/RISCV_Tool/llvm-22.1.8/bin"
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

# ===== 补齐 env/p =====
os.makedirs(ENV_P, exist_ok=True)
for f in os.listdir(ENV_P):
    fp = os.path.join(ENV_P, f)
    if os.path.isfile(fp):
        os.remove(fp)

with open(LD_SCRIPT, "w") as f:
    f.write(LD_CONTENT)

shutil.copy2(os.path.join(TINY_ENV, "riscv_test.h"), os.path.join(ENV_P, "riscv_test.h"))

# 剥离 TEST_* 宏（与原始 macros/scalar/test_macros.h 冲突）
with open(os.path.join(ENV_P, "riscv_test.h"), "r") as f:
    content = f.read()

lines = content.split('\n')
new_lines = []
in_test_section = False
for line in lines:
    if line.strip().startswith('#define TEST_'):
        in_test_section = True
        continue
    if in_test_section:
        stripped = line.strip()
        if stripped == '' or stripped.startswith('//') or stripped.startswith('/*') or stripped.startswith('*/') or stripped.startswith('#'):
            continue
        else:
            in_test_section = False
            new_lines.append(line)
    else:
        new_lines.append(line)

content = '\n'.join(new_lines)
content = re.sub(r'\n{3,}', '\n\n', content)
with open(os.path.join(ENV_P, "riscv_test.h"), "w") as f:
    f.write(content)

print("  [已从 riscv_test.h 剥离 TEST_* 宏]")
print("  [link.ld: 指令 @ 0x10000 / 数据 @ 0x11000]")

# ===== 编译选项 =====
CFLAGS = [
    "-march=rv32im_zicsr_zifencei", "-mabi=ilp32",
    "-static", "-mcmodel=medlow",
    "-nostdlib", "-nostartfiles", "-ffreestanding",
    "-I", os.path.join(RISCV_TESTS, "env", "p"),
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
    elf = os.path.join(OUT_DIR, test_name)
    dump = elf + ".dump"
    dat = elf + ".dat"
    obj = elf + ".o"

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
