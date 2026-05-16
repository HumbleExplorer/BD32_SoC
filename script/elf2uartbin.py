#!/usr/bin/env python3
"""
BD32 SoC UART 下载二进制生成器
将 .elf 文件打包为可直接通过串口发送的 .uartbin 文件。

格式（全部小端字节序）：
  [0x00] START_FRAME  (4B) = 0xBBAABBAA
  [0x04] ITCM_COUNT   (4B) = ITCM 数据字数
  [0x08] ITCM 数据          = ITCM_COUNT × 4B
  [...]  DTCM_COUNT   (4B) = DTCM 数据字数
  [...]  DTCM 数据          = DTCM_COUNT × 4B

用法:
  # 从 ELF 生成
  python elf2uartbin.py program.elf program.uartbin

  # 从汇编源码一步到位
  python elf2uartbin.py program.s program.uartbin --as

  # 从 C 源码一步到位（需指定链接脚本）
  python elf2uartbin.py main.c program.uartbin --c --start start.s --ld link.ld
"""

import sys
import subprocess
import os
import tempfile
import struct

START_FRAME = 0xBBAABBAA
PREFIX = "riscv64-unknown-elf-"


def extract_section_words(elf_path, section_name):
    """用 objcopy 提取段数据，返回 32 位字列表"""
    with tempfile.NamedTemporaryFile(suffix='.bin', delete=False) as f:
        bin_path = f.name

    try:
        result = subprocess.run(
            [PREFIX + 'objcopy', '--dump-section', section_name + '=' + bin_path,
             elf_path, 'nul'],
            capture_output=True, text=True
        )
        if result.returncode != 0:
            return []

        with open(bin_path, 'rb') as f:
            data = f.read()

        if len(data) % 4 != 0:
            data += b'\x00' * (4 - len(data) % 4)

        words = []
        for i in range(0, len(data), 4):
            words.append(int.from_bytes(data[i:i+4], 'little'))
        return words

    finally:
        if os.path.exists(bin_path):
            os.remove(bin_path)


def compile_source(source_path, output_elf_path, is_c=False,
                    startup=None, linker_script=None, include_dir=None):
    """编译 .s 或 .c 源码到 ELF"""
    tmp_files = []

    if is_c:
        # C 程序需要 start.s + 链接脚本
        base_cmd = [PREFIX + 'gcc', '-march=rv32im', '-mabi=ilp32',
                     '-nostartfiles', '-nostdlib', '-ffreestanding', '-Os']
        if include_dir:
            base_cmd += ['-I', include_dir]
        if linker_script:
            base_cmd += ['-T', linker_script]
        base_cmd += ['-o', output_elf_path]

        # 添加源文件
        if startup:
            base_cmd.append(startup)
        base_cmd.append(source_path)

        result = subprocess.run(base_cmd, capture_output=True, text=True)
    else:
        # 汇编程序
        base_obj_path = output_elf_path + '.tmp.o'
        tmp_files.append(base_obj_path)

        # 汇编
        result = subprocess.run(
            [PREFIX + 'as', '-march=rv32im', '-mabi=ilp32',
             '-o', base_obj_path, source_path],
            capture_output=True, text=True
        )
        if result.returncode != 0:
            return False, result.stdout + result.stderr

        # 链接
        ld_cmd = [PREFIX + 'ld', '-melf32lriscv']
        if linker_script:
            ld_cmd += ['-T', linker_script]
        ld_cmd += ['-o', output_elf_path, base_obj_path]
        result = subprocess.run(ld_cmd, capture_output=True, text=True)

    # 清理临时文件
    for f in tmp_files:
        try:
            os.remove(f)
        except:
            pass

    if result.returncode != 0:
        return False, result.stdout + result.stderr
    return True, "OK"


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(1)

    source_path = sys.argv[1]
    output_path = sys.argv[2]
    is_c = '--c' in sys.argv
    startup = None
    linker_script = None
    include_dir = None

    # 解析额外参数
    args = sys.argv[3:]
    for i, arg in enumerate(args):
        if arg == '--start' and i + 1 < len(args):
            startup = args[i + 1]
        elif arg == '--ld' and i + 1 < len(args):
            linker_script = args[i + 1]
        elif arg == '-I' and i + 1 < len(args):
            include_dir = args[i + 1]

    # 自动推断链接脚本和启动代码
    script_dir = os.path.dirname(os.path.abspath(__file__))
    lib_dir = os.path.join(os.path.dirname(script_dir), 'lib')
    if not linker_script:
        linker_script = os.path.join(lib_dir, 'link.ld')
    if is_c and not startup:
        startup = os.path.join(lib_dir, 'start.s')
    if is_c and not include_dir:
        src_dir = os.path.dirname(os.path.abspath(source_path))
        include_dir = src_dir

    # 编译到 ELF
    if source_path.endswith('.c') or is_c:
        print(f"Compiling C: {source_path}")
        print(f"  linker: {linker_script}")
        print(f"  startup: {startup}")
        elf_path = output_path + '.elf.tmp'
        ok, msg = compile_source(source_path, elf_path, is_c=True,
                                  startup=startup, linker_script=linker_script,
                                  include_dir=include_dir)
    elif source_path.endswith('.s'):
        print(f"Assembling: {source_path}")
        elf_path = output_path + '.elf.tmp'
        ok, msg = compile_source(source_path, elf_path, is_c=False,
                                  linker_script=linker_script)
    else:
        # 假定已经是 ELF
        elf_path = source_path
        ok = True

    if not ok:
        print(f"ERROR: Compilation failed:\n{msg}", file=sys.stderr)
        # 清理临时 ELF
        if os.path.exists(elf_path):
            os.remove(elf_path)
        sys.exit(1)

    # 提取段数据
    itcm_sections = ['.init', '.text', '.trap.handler', '.vector_table', '.riscv.jvt']
    dtcm_sections = ['.rodata', '.data', '.sdata']

    itcm_words = []
    dtcm_words = []

    for sec in itcm_sections:
        words = extract_section_words(elf_path, sec)
        if words:
            print(f"  ITCM {sec}: {len(words)} words")
            itcm_words.extend(words)

    for sec in dtcm_sections:
        words = extract_section_words(elf_path, sec)
        if words:
            print(f"  DTCM {sec}: {len(words)} words")
            dtcm_words.extend(words)

    # 清理临时 ELF
    if source_path != elf_path and elf_path.endswith('.elf.tmp'):
        try:
            os.remove(elf_path)
        except:
            pass

    if not itcm_words:
        print("ERROR: No ITCM data found!", file=sys.stderr)
        sys.exit(1)

    # 打包为 UART 二进制格式
    with open(output_path, 'wb') as f:
        # START_FRAME
        f.write(struct.pack('<I', START_FRAME))
        # ITCM_COUNT
        f.write(struct.pack('<I', len(itcm_words)))
        # ITCM 数据
        for w in itcm_words:
            f.write(struct.pack('<I', w))
        # DTCM_COUNT
        f.write(struct.pack('<I', len(dtcm_words)))
        # DTCM 数据
        for w in dtcm_words:
            f.write(struct.pack('<I', w))

    file_size = os.path.getsize(output_path)
    print(f"\n  ITCM: {len(itcm_words)} words")
    print(f"  DTCM: {len(dtcm_words)} words")
    print(f"  File: {output_path} ({file_size} bytes)")
    print(f"\n  直接通过串口发送此文件即可，无需额外帧头。")


if __name__ == '__main__':
    main()
