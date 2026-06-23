#!/bin/bash
# BD32 MROM Build Script
# 
# 用法: bash build_mrom.sh
# 产物: mrom.o, mrom.elf, mrom.bin, mrom.dump, mrom.dat
#
# 工具链: NucleiStudio RISC-V GCC (riscv64-unknown-elf-gcc)
# 架构:   rv32im (支持 mul/div 指令)

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

GCC=riscv64-unknown-elf-gcc
OBJCOPY=llvm-objcopy
OBJDUMP=llvm-objdump

# 如果工具链找不到，尝试绝对路径
if ! command -v $GCC &>/dev/null; then
    GCC="/d/NucleiStudio/toolchain/gcc/bin/$GCC"
    OBJCOPY="/d/NucleiStudio/toolchain/gcc/bin/$OBJCOPY"
    OBJDUMP="/d/NucleiStudio/toolchain/gcc/bin/$OBJDUMP"
fi

ARCH_FLAGS="-march=rv32im -mabi=ilp32"
LD_FLAGS="-nostartfiles -nodefaultlibs -Wl,-Ttext=0x00000000"

echo "=== BD32 MROM Bootloader Build ==="

# 1. Assemble
echo "[1/5] Assembling mrom.s → mrom.o ..."
$GCC -c $ARCH_FLAGS $LD_FLAGS -o mrom.o mrom.s

# 2. Link
echo "[2/5] Linking mrom.o → mrom.elf ..."
$GCC $ARCH_FLAGS $LD_FLAGS -o mrom.elf mrom.o

# 3. Binary
echo "[3/5] Generating mrom.bin ..."
$OBJCOPY -O binary mrom.elf mrom.bin

# 4. Disassembly
echo "[4/5] Generating mrom.dump ..."
$OBJDUMP -d mrom.elf > mrom.dump

# 5. Hex data for simulation ($readmemh)
echo "[5/5] Generating mrom.dat ..."
python3 -c "
import struct
with open('mrom.bin', 'rb') as f:
    data = f.read()
while len(data) % 4:
    data += b'\x00'
words = [f'{struct.unpack(\"<I\", data[i:i+4])[0]:08x}' for i in range(0, len(data), 4)]
with open('mrom.dat', 'w') as f:
    f.write('\n'.join(words) + '\n')
print(f'  {len(words)} words')
"

SIZE=$(wc -c < mrom.bin)
echo ""
echo "=== Build Complete ==="
echo "  Size:  ${SIZE} bytes ($((SIZE / 4)) words)"
echo "  Limit: 4096 bytes (1024 words) for 1K-word MROM"
echo "  Files: mrom.o mrom.elf mrom.bin mrom.dump mrom.dat"
