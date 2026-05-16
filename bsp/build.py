#!/usr/bin/env python3
"""
BD32 SoC BSP 编译助手
用法:
  # 编译 BSP 核心文件
  python bsp/build.py bsp/start.S bsp/init.c bsp/trap_entry.S bsp/trap_handler.c bsp/syscalls.c

  # 编译 demo，链接 BSP，生成 .uartbin
  python bsp/build.py src/demos/timer_irq/main.c --demo -o test_data/custom/demo.uartbin

参数:
  --demo      标记为应用，自动链接 BSP core 和目标
  -o <path>   输出 .uartbin 路径
  -D <flag>   传递额外 define 给编译器
"""

import sys
import os
import subprocess
import tempfile
import struct
import glob

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
WORKING_DIR = os.path.dirname(SCRIPT_DIR)  # Working/
PREFIX = "riscv64-unknown-elf-"
CC = PREFIX + "gcc"
LD = PREFIX + "gcc"
OBJCOPY = PREFIX + "objcopy"
START_FRAME = 0xBBAABBAA

# 默认 BSP core 文件（相对于 Working/bsp/）
BSP_CORE_FILES = [
    "bsp/start.S",
    "bsp/init.c",
    "bsp/vector_table.S",       # 中断向量表 (Vectored) - 替换 trap_entry.S
    "bsp/trap_handler.c",
    "bsp/syscalls.c",
    "bsp/bd32_uart.c",
    "bsp/bd32_clint_asm.S",
]


def compile_core(build_dir):
    """编译 BSP 核心文件"""
    objs = []
    for src_rel in BSP_CORE_FILES:
        src = os.path.join(WORKING_DIR, src_rel)
        if not os.path.exists(src):
            continue
        base = os.path.splitext(os.path.basename(src))[0]
        obj = os.path.join(build_dir, base + ".o")
        # 判断是汇编还是 C
        if src.endswith(".s") or src.endswith(".S"):
            cmd = [CC, "-c", "-march=rv32im", "-mabi=ilp32", "-o", obj, src]
        else:
            cmd = [CC, "-c", "-Os", "-march=rv32im", "-mabi=ilp32",
                   "-fno-lto", "-fno-builtin", "-o", obj, src]
        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode != 0:
            print(f"ERROR compiling {src_rel}:", result.stderr)
            sys.exit(1)
        print(f"  CC {src_rel}")
        objs.append(obj)
    return objs


def compile_source(src, build_dir, defines=None):
    """编译一个源文件"""
    base = os.path.splitext(os.path.basename(src))[0]
    obj = os.path.join(build_dir, base + ".o")
    if src.endswith(".s") or src.endswith(".S"):
        cmd = [CC, "-c", "-march=rv32im", "-mabi=ilp32", "-I", os.path.join(WORKING_DIR, "bsp"), "-o", obj, src]
    else:
        cmd = [CC, "-c", "-Os", "-march=rv32im", "-mabi=ilp32",
               "-fno-lto", "-fno-builtin", "-I", os.path.join(WORKING_DIR, "bsp"),
               "-o", obj, src]
    if defines:
        for d in defines:
            cmd.append(f"-D{d}")
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"ERROR compiling {src}:", result.stderr)
        sys.exit(1)
    print(f"  CC {os.path.relpath(src, WORKING_DIR)}")
    return obj


def link(core_objs, app_obj, build_dir):
    """链接并生成 ELF"""
    elf = os.path.join(build_dir, "output.elf")
    ldscript = os.path.join(WORKING_DIR, "bsp", "link.ld")
    all_objs = core_objs + [app_obj]
    cmd = [LD, "-march=rv32im", "-mabi=ilp32",
           "-nostartfiles", "-nodefaultlibs",
           "-T", ldscript, "-o", elf] + all_objs
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"ERROR linking:", result.stderr)
        sys.exit(1)
    print(f"  LD output.elf")
    return elf


def elf_to_uartbin(elf_path, output_path):
    """将 ELF 打包为 .uartbin"""
    itcm_sections = ['.reset', '.trap.vector', '.init', '.text', '.trap.handler', '.vector_table', '.riscv.jvt']
    dtcm_sections = ['.rodata', '.data', '.sdata']
    itcm_words = []
    dtcm_words = []

    for sec in itcm_sections:
        with tempfile.NamedTemporaryFile(suffix='.bin', delete=False) as f:
            bin_path = f.name
        result = subprocess.run(
            [OBJCOPY, '--dump-section', sec + '=' + bin_path, elf_path, 'nul'],
            capture_output=True, text=True
        )
        if result.returncode == 0:
            with open(bin_path, 'rb') as f:
                data = f.read()
            if len(data) % 4 != 0:
                data += b'\x00' * (4 - len(data) % 4)
            words = [int.from_bytes(data[i:i+4], 'little') for i in range(0, len(data), 4)]
            if words:
                print(f"  ITCM {sec}: {len(words)} words")
                itcm_words.extend(words)
        if os.path.exists(bin_path):
            os.remove(bin_path)

    for sec in dtcm_sections:
        with tempfile.NamedTemporaryFile(suffix='.bin', delete=False) as f:
            bin_path = f.name
        result = subprocess.run(
            [OBJCOPY, '--dump-section', sec + '=' + bin_path, elf_path, 'nul'],
            capture_output=True, text=True
        )
        if result.returncode == 0:
            with open(bin_path, 'rb') as f:
                data = f.read()
            if len(data) % 4 != 0:
                data += b'\x00' * (4 - len(data) % 4)
            words = [int.from_bytes(data[i:i+4], 'little') for i in range(0, len(data), 4)]
            if words:
                print(f"  DTCM {sec}: {len(words)} words")
                dtcm_words.extend(words)
        if os.path.exists(bin_path):
            os.remove(bin_path)

    if not itcm_words:
        print("ERROR: No ITCM data found!")
        sys.exit(1)

    with open(output_path, 'wb') as f:
        f.write(struct.pack('<I', START_FRAME))
        f.write(struct.pack('<I', len(itcm_words)))
        for w in itcm_words:
            f.write(struct.pack('<I', w))
        f.write(struct.pack('<I', len(dtcm_words)))
        for w in dtcm_words:
            f.write(struct.pack('<I', w))

    file_size = os.path.getsize(output_path)
    print(f"\n  ITCM: {len(itcm_words)} words, DTCM: {len(dtcm_words)} words")
    print(f"  Output: {output_path} ({file_size} bytes)")


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)

    build_dir = tempfile.mkdtemp()
    output_path = None
    defines = []

    # 解析参数
    args = [a for a in sys.argv[1:] if not a.startswith('-D')]
    for i, a in enumerate(sys.argv[1:]):
        if a.startswith('-D'):
            defines.append(a[2:])

    is_demo = False
    positional = []
    i = 0
    while i < len(args):
        if args[i] == '--demo':
            is_demo = True
        elif args[i] == '-o' and i + 1 < len(args):
            output_path = args[i + 1]
            i += 1
        else:
            positional.append(args[i])
        i += 1

    # 编译 core + 目标
    core_objs = compile_core(build_dir)
    target_obj = compile_source(positional[0], build_dir, defines)

    # 链接
    elf_path = link(core_objs, target_obj, build_dir)

    # 生成 .uartbin
    if not output_path:
        output_path = os.path.splitext(positional[0])[0] + ".uartbin"

    elf_to_uartbin(elf_path, output_path)

    # 清理
    for f in core_objs + [target_obj]:
        try:
            os.remove(f)
        except:
            pass
    try:
        os.remove(elf_path)
    except:
        pass
    import shutil
    shutil.rmtree(build_dir, ignore_errors=True)


if __name__ == '__main__':
    main()
