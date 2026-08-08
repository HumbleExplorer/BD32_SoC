#!/bin/bash
# BD32 诊断 MROM Build Script (xPack toolchain)
# 产物: mrom_diag.o, mrom_diag.elf, mrom_diag.bin, mrom_diag.dump, mrom_diag.dat, mrom_diag.coe

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

SRC="mrom_diag.s"
BASE="mrom_diag"

echo "=== BD32 Diagnostic MROM Build ==="

echo "[1/6] Assembling $SRC -> ${BASE}.o ..."
"$GCC" -c $ARCH_FLAGS $LD_FLAGS -o ${BASE}.o $SRC

echo "[2/6] Linking ${BASE}.o -> ${BASE}.elf ..."
"$GCC" $ARCH_FLAGS $LD_FLAGS -o ${BASE}.elf ${BASE}.o

echo "[3/6] Generating ${BASE}.bin ..."
"$OBJCOPY" -O binary ${BASE}.elf ${BASE}.bin

echo "[4/6] Generating ${BASE}.dump ..."
"$OBJDUMP" -d ${BASE}.elf > ${BASE}.dump

echo "[5/6] Generating ${BASE}.dat ..."
"$PY" - <<'EOF'
import struct
data = open('mrom_diag.bin', 'rb').read()
while len(data) % 4:
    data += b'\x00'
words = ['%08x' % struct.unpack('<I', data[i:i+4])[0] for i in range(0, len(data), 4)]
open('mrom_diag.dat', 'w').write('\n'.join(words) + '\n')
print('  %d words' % len(words))
EOF

echo "[6/6] Generating ${BASE}.coe ..."
"$PY" - <<'EOF'
import struct
data = open('mrom_diag.bin', 'rb').read()
while len(data) % 4:
    data += b'\x00'
words = ['%08X' % struct.unpack('<I', data[i:i+4])[0] for i in range(0, len(data), 4)]
while len(words) < 1024:
    words.append('00000000')
open('mrom_diag.coe', 'w').write('memory_initialization_radix=16;\nmemory_initialization_vector=\n' + '\n'.join(words) + ';')
print('  %d words (padded to 1024)' % len(words))
EOF

SIZE=$(wc -c < ${BASE}.bin)
echo ""
echo "=== Build Complete ==="
echo "  Size:  ${SIZE} bytes ($((SIZE / 4)) words)"
echo "  Limit: 4096 bytes (1024 words) for 1K-word MROM"
echo "  Files: ${BASE}.o ${BASE}.elf ${BASE}.bin ${BASE}.dump ${BASE}.dat ${BASE}.coe"
