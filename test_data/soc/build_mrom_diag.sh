#!/bin/bash
# BD32 诊断 MROM Build Script
# 产物: mrom_diag.o, mrom_diag.elf, mrom_diag.bin, mrom_diag.dump, mrom_diag.dat, mrom_diag.coe

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

GCC=riscv64-unknown-elf-gcc
OBJCOPY=llvm-objcopy
OBJDUMP=llvm-objdump

if ! command -v $GCC &>/dev/null; then
    GCC="/d/NucleiStudio/toolchain/gcc/bin/$GCC"
    OBJCOPY="/d/NucleiStudio/toolchain/gcc/bin/$OBJCOPY"
    OBJDUMP="/d/NucleiStudio/toolchain/gcc/bin/$OBJDUMP"
fi

ARCH_FLAGS="-march=rv32im -mabi=ilp32"
LD_FLAGS="-nostartfiles -nodefaultlibs -Wl,-Ttext=0x00000000"

SRC="mrom_diag.s"
BASE="mrom_diag"

echo "=== BD32 Diagnostic MROM Build ==="

# 1. Assemble
echo "[1/6] Assembling $SRC → ${BASE}.o ..."
$GCC -c $ARCH_FLAGS $LD_FLAGS -o ${BASE}.o $SRC

# 2. Link
echo "[2/6] Linking ${BASE}.o → ${BASE}.elf ..."
$GCC $ARCH_FLAGS $LD_FLAGS -o ${BASE}.elf ${BASE}.o

# 3. Binary
echo "[3/6] Generating ${BASE}.bin ..."
$OBJCOPY -O binary ${BASE}.elf ${BASE}.bin

# 4. Disassembly
echo "[4/6] Generating ${BASE}.dump ..."
$OBJDUMP -d ${BASE}.elf > ${BASE}.dump

# 5. Hex data for simulation ($readmemh)
echo "[5/6] Generating ${BASE}.dat ..."
python3 -c "
import struct
with open('${BASE}.bin', 'rb') as f:
    data = f.read()
while len(data) % 4:
    data += b'\x00'
words = [f'{struct.unpack(\"<I\", data[i:i+4])[0]:08x}' for i in range(0, len(data), 4)]
with open('${BASE}.dat', 'w') as f:
    f.write('\n'.join(words) + '\n')
print(f'  {len(words)} words')
"

# 6. COE for Xilinx BRAM init
echo "[6/6] Generating ${BASE}.coe ..."
python3 -c "
import struct
with open('${BASE}.bin', 'rb') as f:
    data = f.read()
while len(data) % 4:
    data += b'\x00'
words = [f'{struct.unpack(\"<I\", data[i:i+4])[0]:08X}' for i in range(0, len(data), 4)]
# Pad to 1024 words (MROM depth)
while len(words) < 1024:
    words.append('00000000')
with open('${BASE}.coe', 'w') as f:
    f.write('memory_initialization_radix=16;\n')
    f.write('memory_initialization_vector=\n')
    f.write('\n'.join(words) + ';\n')
print(f'  {len(words)} words (padded to 1024)')
"

SIZE=$(wc -c < ${BASE}.bin)
echo ""
echo "=== Build Complete ==="
echo "  Size:  ${SIZE} bytes ($((SIZE / 4)) words)"
echo "  Limit: 4096 bytes (1024 words) for 1K-word MROM"
echo "  Files: ${BASE}.o ${BASE}.elf ${BASE}.bin ${BASE}.dump ${BASE}.dat ${BASE}.coe"
