#!/bin/bash
# ============================================================================
# build_asm.sh — 构建「自定义汇编测试」(custom_asm)
#
# 与官方 riscv-tests 共享同一套底层文件：
#   SDK/isa/env/p/link.ld      (链接脚本，.text.init @0x10000)
#   SDK/isa/env/p/riscv_test.h (含 _start / RVTEST_PASS/FAIL / trap)
#   SDK/isa/macros/scalar/        (test_macros.h)
# 因此本脚本产出的 .dat 可直接被 core_test 的 ITCM 直接加载（无 bootROM）。
#
# 产物（与 .S 同目录）：
#   <name>.elf   链接后的 ELF（带符号，可配合 addr2line/gdb）
#   <name>.dump  objdump -dS 反汇编（源码+标签，调试用）
#   <name>.dat    $readmemh 用的字流（8 位小写 hex/字，与 riscv-tests 同格式）
#
# 用法：
#   ./build_asm.sh bd32_mul_stress        # 构建单个
#   ./build_asm.sh all                      # 构建目录下所有 *.S
#   ./build_asm.sh -h | --help              # 帮助
# ============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# 仓库根：custom_asm -> up2 = Working/
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# Windows .exe 工具（gcc/python）只认 Windows 风格路径；Git Bash 的 /d/... 它不认
REPO_ROOT_WIN="$(cygpath -w "$REPO_ROOT" | sed 's/\\/\//g')"

TOOLCHAIN="${RISCV_TOOLCHAIN:-D:/RISCV_Tool/xpack-riscv-none-elf-gcc-15.2.0-1/bin}"
GCC="$TOOLCHAIN/riscv-none-elf-gcc"
OBJCOPY="$TOOLCHAIN/riscv-none-elf-objcopy"
OBJDUMP="$TOOLCHAIN/riscv-none-elf-objdump"

LINK="$REPO_ROOT_WIN/SDK/isa/env/p/link.ld"
INC1="$REPO_ROOT_WIN/SDK/isa/env/p"
INC2="$REPO_ROOT_WIN/SDK/isa/macros/scalar"

build_one() {
    local name="$1"
    local S="$name.S"
    [ -f "$S" ] || { echo "ERROR: $S not found"; return 1; }
    echo "=== build_asm: $name ==="

    # 1) 汇编 + 链接（共享 riscv-tests 的 link.ld / riscv_test.h）
    "$GCC" -march=rv32im -mabi=ilp32 -O0 -mno-relax -Wl,--no-relax \
        -T "$LINK" -I "$INC1" -I "$INC2" \
        -nostdlib -static -o "$name.elf" "$S"

    # 2) 反汇编（源码交织）
    "$OBJDUMP" -dS "$name.elf" > "$name.dump"

    # 3) ELF -> 纯二进制（.text 小端字节流）
    "$OBJCOPY" -O binary "$name.elf" "$name.bin"

    # 4) 二进制 -> .dat（4 字节小端 -> %08x 每行一字，与 $readmemh 完全一致）
    local PYBIN
    PYBIN="${PYTHON:-D:/Python312/python.exe}"
    "$PYBIN" - "$name.bin" "$name.dat" <<'PY'
import sys
data = open(sys.argv[1], 'rb').read()
if len(data) % 4:
    data += b'\x00' * (4 - (len(data) % 4))
words = [data[i:i+4] for i in range(0, len(data), 4)]
with open(sys.argv[2], 'w') as f:
    for w in words:
        f.write('%08x\n' % int.from_bytes(w, 'little'))
print('  DAT: %d words -> %s' % (len(words), sys.argv[2]))
PY

    rm -f "$name.bin"
    echo "  OK: $name.elf / $name.dump / $name.dat"
}

case "$1" in
    ""|-h|--help)
        sed -n '2,20p' "$0"
        ;;
    all)
        shopt -s nullglob
        files=(*.S)
        if [ ${#files[@]} -eq 0 ]; then
            echo "ERROR: no *.S found in $(pwd)"
            exit 1
        fi
        for s in "${files[@]}"; do
            build_one "${s%.S}"
        done
        ;;
    *)
        build_one "$1"
        ;;
esac
