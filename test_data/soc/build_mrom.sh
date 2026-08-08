#!/bin/bash
# BD32 MROM Build Script (xPack toolchain)
#
# 用法: bash build_mrom.sh
# 产物: mrom.o, mrom.elf, mrom.bin, mrom.dump, mrom.dat, mrom.coe
#
# 工具链: xPack riscv-none-elf-gcc
# 架构:   rv32im_zicsr (MROM 使用 csrr/csrw，必须显式加 zicsr)

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

TC="/d/RISCV_Tool/xpack-riscv-none-elf-gcc-15.2.0-1/bin"
GCC="$TC/riscv-none-elf-gcc"
OBJCOPY="$TC/riscv-none-elf-objcopy"
OBJDUMP="$TC/riscv-none-elf-objdump"
PY=python3

ARCH_FLAGS="-march=rv32im_zicsr -mabi=ilp32"
LD_FLAGS="-nostartfiles -nodefaultlibs -Wl,-Ttext=0x00000000"

echo "=== BD32 MROM Bootloader Build ==="

echo "[1/6] Assembling mrom.s -> mrom.o ..."
"$GCC" -c $ARCH_FLAGS $LD_FLAGS -o mrom.o mrom.s

echo "[2/6] Linking mrom.o -> mrom.elf ..."
"$GCC" $ARCH_FLAGS $LD_FLAGS -o mrom.elf mrom.o

echo "[3/6] Generating mrom.bin ..."
"$OBJCOPY" -O binary mrom.elf mrom.bin

echo "[4/6] Generating mrom.dump ..."
"$OBJDUMP" -d mrom.elf > mrom.dump

echo "[5/6] Generating mrom.dat + mrom.coe ..."
"$PY" - <<'EOF'
import struct
data = open('mrom.bin', 'rb').read()
while len(data) % 4:
    data += b'\x00'
words = ['%08x' % struct.unpack('<I', data[i:i+4])[0] for i in range(0, len(data), 4)]
open('mrom.dat', 'w').write('\n'.join(words) + '\n')
open('mrom.coe', 'w').write('memory_initialization_radix=16;\nmemory_initialization_vector=\n' + '\n'.join(words) + ';')
print('  %d words' % len(words))
EOF

SIZE=$(wc -c < mrom.bin)
echo ""
echo "=== Build Complete ==="
echo "  Size:  ${SIZE} bytes ($((SIZE / 4)) words)"
echo "  Limit: 4096 bytes (1024 words) for 1K-word MROM"
echo "  Files: mrom.o mrom.elf mrom.bin mrom.dump mrom.dat mrom.coe"
