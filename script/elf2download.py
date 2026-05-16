#!/usr/bin/env python3
"""
BD32 SoC 下载文件生成器（计数协议版）
从 ELF 文件提取 .text 段 (ITCM) 和 .rodata/.data 段 (DTCM)，
生成计数格式下载文件。

格式：
  第1行: ITCM 字数（十六进制，如 00000018）
  第2行起: ITCM 指令数据
  之后: DTCM 数据

用法: python elf2download.py <input.elf> <output.download>
"""

import sys
import subprocess
import os
import tempfile

PREFIX = "riscv64-unknown-elf-"


def extract_section_words(elf_path, section_name):
    """用 objcopy --dump-section 提取段数据，返回 32 位字列表"""
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


def main():
    if len(sys.argv) < 3:
        print("Usage: python elf2download.py <input.elf> <output.download>")
        sys.exit(1)

    elf_path = sys.argv[1]
    out_path = sys.argv[2]

    print(f"Reading ELF: {elf_path}")

    # ITCM 段: .init, .text, .trap.handler, .vector_table
    itcm_sections = ['.init', '.text', '.trap.handler', '.vector_table', '.riscv.jvt']
    # DTCM 段
    dtcm_sections = ['.rodata', '.data', '.sdata']

    itcm_words = []
    dtcm_words = []

    for sec in itcm_sections:
        words = extract_section_words(elf_path, sec)
        if words:
            print(f"  ITCM {sec}: {len(words)} words ({len(words)*4} bytes)")
            itcm_words.extend(words)

    for sec in dtcm_sections:
        words = extract_section_words(elf_path, sec)
        if words:
            print(f"  DTCM {sec}: {len(words)} words ({len(words)*4} bytes)")
            dtcm_words.extend(words)

    if not itcm_words:
        print("ERROR: No ITCM data found!", file=sys.stderr)
        sys.exit(1)

    # 计数协议格式: [ITCM_COUNT][ITCM words][DTCM words]
    with open(out_path, 'w') as f:
        # 第1行: ITCM 字数
        f.write(f'{len(itcm_words):08x}\n')
        # ITCM 数据
        for w in itcm_words:
            f.write(f'{w:08x}\n')
        # DTCM 数据
        for w in dtcm_words:
            f.write(f'{w:08x}\n')

    total = 1 + len(itcm_words) + len(dtcm_words)  # 包含 count 行
    print(f"\n  ITCM: {len(itcm_words)} words")
    print(f"  DTCM: {len(dtcm_words)} words")
    print(f"  Total lines: {total}")
    print(f"  Output: {out_path}")


if __name__ == '__main__':
    main()
