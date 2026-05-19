#!/usr/bin/env python3
"""
BD32 SoC 统一构建工具

从 C 源码、汇编源码或 ELF 文件生成多种输出格式：
  .elf    - ELF 可执行文件
  .dump   - 反汇编文本
  .uartbin- UART 下载二进制（含帧头，上板用）
  .mem    - $readmemh 兼容的 hex 文本格式（ITCM/DTCM 仿真直接加载用）
  .dat    - 裸 hex 文本格式（每行一个 32 位字，riscv-tests 风格）
  .hex    - Intel HEX 格式

用法:
  # 汇编程序 → 所有格式
  python build.py myprog.s

  # C 程序 → 所有格式（自动查找 lib/link.ld 和 lib/start.s）
  python build.py main.c

  # 仅生成指定格式
  python build.py main.c --formats elf,dump,mem

  # 指定输出目录和文件名
  python build.py main.c --output-dir ../test_data/custom --output-name demo

  # 手动指定链接脚本和启动代码
  python build.py main.c --ld ../lib/link.ld --start ../lib/start.s -I ../src

  # 从已有 ELF 生成其他格式
  python build.py program.elf --formats uartbin,mem,dump
"""

import sys
import subprocess
import os
import tempfile
import struct
import argparse

# ============================================================
# 工具链配置
# ============================================================
PREFIX = "riscv64-unknown-elf-"
AS      = PREFIX + "as"
LD      = PREFIX + "ld"
CC      = PREFIX + "gcc"
OBJCOPY = PREFIX + "objcopy"
OBJDUMP = PREFIX + "objdump"

# 默认 ITCM/DTCM 段
ITCM_SECTIONS = ['.init', '.text', '.trap.handler', '.vector_table', '.riscv.jvt']
DTCM_SECTIONS = ['.rodata', '.data', '.sdata']

# UART 下载帧头
START_FRAME = 0xBBAABBAA

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
WORKING_DIR = os.path.dirname(SCRIPT_DIR)  # Working/
LIB_DIR = os.path.join(WORKING_DIR, 'lib')


# ============================================================
# 工具函数
# ============================================================

def run_cmd(cmd, desc="", verbose=False):
    """执行命令，返回 (ok, stdout+stderr)"""
    if verbose:
        print(f"  $ {' '.join(cmd)}")
    try:
        result = subprocess.run(cmd, capture_output=True, text=True)
        output = result.stdout + result.stderr
        if result.returncode != 0:
            return False, output
        return True, output
    except FileNotFoundError:
        return False, f"Command not found: {cmd[0]}"
    except Exception as e:
        return False, str(e)


def extract_words_from_elf(elf_path, sections, verbose=False):
    """从 ELF 的指定段提取 32 位字列表"""
    words = []
    with tempfile.NamedTemporaryFile(suffix='.bin', delete=False) as f:
        bin_path = f.name
    try:
        for sec in sections:
            ok, _ = run_cmd(
                [OBJCOPY, '--dump-section', f'{sec}={bin_path}', elf_path, 'nul'],
                verbose=verbose
            )
            if not ok:
                continue
            with open(bin_path, 'rb') as f:
                data = f.read()
            if len(data) == 0:
                continue
            # 补齐到 4 字节对齐
            if len(data) % 4 != 0:
                data += b'\x00' * (4 - len(data) % 4)
            sec_words = []
            for i in range(0, len(data), 4):
                sec_words.append(int.from_bytes(data[i:i+4], 'little'))
            if verbose:
                print(f"    {sec}: {len(sec_words)} words")
            words.extend(sec_words)
    finally:
        try:
            os.remove(bin_path)
        except OSError:
            pass
    return words


def words_to_lines(words):
    """将 32 位字列表转换为每行一个 hex 的文本行列表"""
    return [f'{w:08x}' for w in words]


# ============================================================
# 编译
# ============================================================

def compile_c(source, output_elf, linker_script, startup, include_dirs,
              verbose=False):
    """编译 C 程序 → ELF"""
    cmd = [
        CC, '-march=rv32im', '-mabi=ilp32',
        '-nostartfiles', '-nostdlib', '-ffreestanding', '-Os',
        '-T', linker_script,
        '-o', output_elf,
    ]
    for d in include_dirs:
        cmd += ['-I', d]
    if startup:
        cmd.append(startup)
    cmd.append(source)
    return run_cmd(cmd, desc="Compiling C", verbose=verbose)


def compile_asm(source, output_elf, linker_script=None, verbose=False):
    """编译汇编程序 → ELF"""
    # 汇编
    with tempfile.NamedTemporaryFile(suffix='.o', delete=False) as f:
        obj_path = f.name
    ok, msg = run_cmd(
        [AS, '-march=rv32im', '-mabi=ilp32', '-o', obj_path, source],
        desc="Assembling", verbose=verbose
    )
    if not ok:
        try: os.remove(obj_path)
        except: pass
        return False, msg

    # 链接
    ld_cmd = [LD, '-melf32lriscv', '-o', output_elf, obj_path]
    if linker_script:
        ld_cmd = [LD, '-melf32lriscv', '-T', linker_script, '-o', output_elf, obj_path]
    ok, msg = run_cmd(ld_cmd, desc="Linking", verbose=verbose)
    try: os.remove(obj_path)
    except: pass
    return ok, msg


# ============================================================
# 输出格式生成
# ============================================================

def gen_dump(elf_path, output_path, verbose=False):
    """生成反汇编 .dump"""
    ok, _ = run_cmd(
        [OBJDUMP, '-d', elf_path],
        verbose=verbose
    )
    if not ok:
        return False
    with open(elf_path, 'rb') as _: pass  # sanity check
    ok, output = run_cmd(
        [OBJDUMP, '-d', elf_path],
        verbose=verbose
    )
    if not ok:
        return False, "objdump failed"
    with open(output_path, 'w') as f:
        f.write(output)
    if verbose:
        print(f"    -> {output_path}")
    return True, ""


def gen_mem(elf_path, output_path_itcm, output_path_dtcm, verbose=False):
    """生成 .mem 格式（$readmemh 兼容，每行一个 32 位 hex）
    ITCM .mem：指令段（.init + .text + .trap.handler + .vector_table）
    DTCM .mem：数据段（.rodata + .data + .sdata）
    若某段为空则输出空文件（仅包含一行 00000000 占位）
    """
    itcm_words = extract_words_from_elf(elf_path, ITCM_SECTIONS, verbose)
    dtcm_words = extract_words_from_elf(elf_path, DTCM_SECTIONS, verbose)

    # 写 ITCM .mem
    if itcm_words:
        with open(output_path_itcm, 'w') as f:
            for w in itcm_words:
                f.write(f'{w:08x}\n')
        if verbose:
            print(f"    ITCM .mem: {len(itcm_words)} words -> {output_path_itcm}")
    else:
        with open(output_path_itcm, 'w') as f:
            f.write('00000000\n')
        if verbose:
            print(f"    ITCM .mem: (empty, wrote placeholder) -> {output_path_itcm}")

    # 写 DTCM .mem
    if dtcm_words:
        with open(output_path_dtcm, 'w') as f:
            for w in dtcm_words:
                f.write(f'{w:08x}\n')
        if verbose:
            print(f"    DTCM .mem: {len(dtcm_words)} words -> {output_path_dtcm}")
    else:
        with open(output_path_dtcm, 'w') as f:
            pass  # 空文件（没有数据段时 DTCM 可以为空）
        if verbose:
            print(f"    DTCM .mem: (empty) -> {output_path_dtcm}")

    return True, ""


def gen_uartbin(elf_path, output_path, verbose=False):
    """生成 UART 下载二进制 .uartbin"""
    itcm_words = extract_words_from_elf(elf_path, ITCM_SECTIONS, verbose)
    dtcm_words = extract_words_from_elf(elf_path, DTCM_SECTIONS, verbose)

    if not itcm_words:
        return False, "No ITCM data found"

    with open(output_path, 'wb') as f:
        # START_FRAME
        f.write(struct.pack('<I', START_FRAME))
        # ITCM_COUNT
        f.write(struct.pack('<I', len(itcm_words)))
        # ITCM data
        for w in itcm_words:
            f.write(struct.pack('<I', w))
        # DTCM_COUNT
        f.write(struct.pack('<I', len(dtcm_words)))
        # DTCM data
        for w in dtcm_words:
            f.write(struct.pack('<I', w))

    size = os.path.getsize(output_path)
    if verbose:
        print(f"    ITCM: {len(itcm_words)} words, DTCM: {len(dtcm_words)} words")
        print(f"    -> {output_path} ({size} bytes)")
    return True, ""


def gen_dat(elf_path, output_path, verbose=False):
    """生成 .dat 格式（裸 hex，ITCM + DTCM 连续拼接，riscv-tests 风格）"""
    itcm_words = extract_words_from_elf(elf_path, ITCM_SECTIONS, verbose)
    dtcm_words = extract_words_from_elf(elf_path, DTCM_SECTIONS, verbose)

    all_words = itcm_words + dtcm_words
    if not all_words:
        return False, "No data found"

    with open(output_path, 'w') as f:
        for w in all_words:
            f.write(f'{w:08x}\n')

    if verbose:
        print(f"    -> {output_path} ({len(all_words)} words)")
    return True, ""


def gen_hex(elf_path, output_path, verbose=False):
    """生成 Intel HEX 格式"""
    with tempfile.NamedTemporaryFile(suffix='.hex', delete=False) as f:
        tmp_hex = f.name
    try:
        ok, msg = run_cmd(
            [OBJCOPY, '-O', 'ihex', elf_path, tmp_hex],
            verbose=verbose
        )
        if not ok:
            return False, msg
        # 复制到目标路径
        with open(tmp_hex, 'r') as src:
            content = src.read()
        with open(output_path, 'w') as dst:
            dst.write(content)
        if verbose:
            size = os.path.getsize(output_path)
            print(f"    -> {output_path} ({size} bytes)")
        return True, ""
    finally:
        try: os.remove(tmp_hex)
        except: pass


# 格式调度表：格式名 → (生成函数, 扩展名, 描述)
FORMATS = {
    'dump':     (gen_dump,     '.dump',     '反汇编文本'),
    'uartbin':  (gen_uartbin,  '.uartbin',  'UART 下载二进制（含帧头）'),
    'mem':      (gen_mem,      '.mem',      'hex 文本格式（$readmemh 兼容）'),
    'dat':      (gen_dat,      '.dat',      '裸 hex 文本格式'),
    'hex':      (gen_hex,      '.hex',      'Intel HEX 格式'),
}


# ============================================================
# 入口
# ============================================================

def main():
    parser = argparse.ArgumentParser(
        description='BD32 SoC 统一构建工具',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__
    )
    parser.add_argument('input', help='输入文件 (.s / .c / .elf)')
    parser.add_argument('--output-dir', '-o', default=None,
                        help='输出目录（默认：输入文件所在目录）')
    parser.add_argument('--output-name', '-n', default=None,
                        help='输出文件名前缀（默认：输入文件名）')
    parser.add_argument('--ld', default=None,
                        help='链接脚本路径（C 程序必需，汇编可选）')
    parser.add_argument('--start', default=None,
                        help='启动代码路径（C 程序必需）')
    parser.add_argument('-I', '--include', dest='include_dirs', action='append',
                        default=[], help='头文件搜索路径（可重复）')
    parser.add_argument('--formats', default=None,
                        help=f'输出格式，逗号分隔。可选: all,{",".join(FORMATS.keys())} （默认：全部）')
    parser.add_argument('--asm', action='store_true',
                        help='强制汇编模式')
    parser.add_argument('--c', dest='c_mode', action='store_true',
                        help='强制 C 模式')
    parser.add_argument('--verbose', '-v', action='store_true',
                        help='详细输出')
    parser.add_argument('--keep-elf', action='store_true',
                        help='保留编译中间产物 .elf 文件（默认清理）')

    args = parser.parse_args()

    input_path = args.input
    if not os.path.exists(input_path):
        print(f"[ERROR] Input file not found: {input_path}")
        sys.exit(1)

    input_name = os.path.basename(input_path)
    input_base = os.path.splitext(input_name)[0]
    input_dir = os.path.dirname(os.path.abspath(input_path))
    ext = os.path.splitext(input_name)[1].lower()

    # 确定输出目录
    out_dir = args.output_dir
    if out_dir:
        out_dir = os.path.abspath(out_dir)
        os.makedirs(out_dir, exist_ok=True)
    else:
        out_dir = input_dir

    # 确定输出文件名前缀
    out_base = args.output_name if args.output_name else input_base

    # 确定输出格式列表
    if args.formats:
        raw_list = [f.strip() for f in args.formats.split(',')]
        # 展开 'all' → 全部格式
        if 'all' in raw_list:
            fmt_list = list(FORMATS.keys())
        else:
            fmt_list = raw_list
        for f in fmt_list:
            if f not in FORMATS:
                print(f"[ERROR] Unknown format: {f}")
                print(f"  Available: all,{', '.join(FORMATS.keys())}")
                sys.exit(1)
    else:
        fmt_list = list(FORMATS.keys())

    # ============================================================
    # Step 1: 编译 → ELF
    # ============================================================
    is_elf_input = (ext == '.elf')
    elf_path = None
    temp_elf = None

    if is_elf_input:
        # 直接使用输入的 ELF
        elf_path = input_path
        print(f"[INFO] Input is ELF: {input_path}")
    else:
        # 需要编译
        is_c = args.c_mode or ext == '.c'
        temp_elf = os.path.join(out_dir, f'{out_base}.elf')
        elf_path = temp_elf

        # 自动查找 lib 目录下的文件
        if is_c:
            ld_script = args.ld
            if not ld_script:
                default_ld = os.path.join(LIB_DIR, 'link.ld')
                if os.path.exists(default_ld):
                    ld_script = default_ld
                    if args.verbose:
                        print(f"  [auto] linker script: {ld_script}")
            start_code = args.start
            if not start_code:
                default_start = os.path.join(LIB_DIR, 'start.s')
                if os.path.exists(default_start):
                    start_code = default_start
                    if args.verbose:
                        print(f"  [auto] startup: {start_code}")
            include_dirs = args.include_dirs if args.include_dirs else []
            if not include_dirs:
                include_dirs.append(input_dir)
                # 也把 src/ 加入搜索路径
                src_dir = os.path.join(WORKING_DIR, 'src')
                if os.path.exists(src_dir):
                    include_dirs.append(src_dir)
                lib_inc = os.path.join(WORKING_DIR, 'lib')
                if os.path.exists(lib_inc):
                    include_dirs.append(lib_inc)

            print(f"[BUILD] Compiling C: {input_name}")
            if args.verbose:
                print(f"  linker: {ld_script}")
                print(f"  startup: {start_code}")
            ok, msg = compile_c(input_path, temp_elf, ld_script, start_code,
                                include_dirs, verbose=args.verbose)
            if not ok:
                print(f"[ERROR] C compilation failed:\n{msg.strip()}")
                # 清理
                if os.path.exists(temp_elf):
                    os.remove(temp_elf)
                sys.exit(1)
            print(f"  -> {temp_elf}")

        else:
            # 汇编模式
            ld_script = args.ld
            print(f"[BUILD] Assembling: {input_name}")
            if args.verbose and ld_script:
                print(f"  linker: {ld_script}")
            ok, msg = compile_asm(input_path, temp_elf, ld_script,
                                  verbose=args.verbose)
            if not ok:
                print(f"[ERROR] Assembly failed:\n{msg.strip()}")
                if os.path.exists(temp_elf):
                    os.remove(temp_elf)
                sys.exit(1)
            print(f"  -> {temp_elf}")

    # ============================================================
    # Step 2: 验证 ELF
    # ============================================================
    if not os.path.exists(elf_path) or os.path.getsize(elf_path) == 0:
        print(f"[ERROR] ELF file invalid: {elf_path}")
        sys.exit(1)

    # ============================================================
    # Step 3: 生成各格式
    # ============================================================
    print(f"\n[GEN] Generating output formats: {', '.join(fmt_list)}")

    # mem 格式特殊：需要生成两个文件（itcm + dtcm）
    # 先处理 mem，再处理其他单文件格式
    mem_dtcm_path = None

    for fmt_name in fmt_list:
        gen_func, ext_name, desc = FORMATS[fmt_name]

        if fmt_name == 'mem':
            # mem 格式生成两个文件
            out_itcm = os.path.join(out_dir, f'{out_base}_itcm{ext_name}')
            out_dtcm = os.path.join(out_dir, f'{out_base}_dtcm{ext_name}')
            mem_dtcm_path = out_dtcm  # 记下备用
            ok, msg = gen_func(elf_path, out_itcm, out_dtcm,
                               verbose=args.verbose)
            if not ok:
                print(f"  [WARN] mem generation issue: {msg}")
            else:
                print(f"  [OK]  {desc:20s} -> {os.path.basename(out_itcm)}, {os.path.basename(out_dtcm)}")
            continue

        # 单文件格式
        out_path = os.path.join(out_dir, f'{out_base}{ext_name}')

        if fmt_name == 'dat':
            ok, msg = gen_func(elf_path, out_path, verbose=args.verbose)
        elif fmt_name == 'dump':
            ok, msg = gen_func(elf_path, out_path, verbose=args.verbose)
        elif fmt_name == 'uartbin':
            ok, msg = gen_func(elf_path, out_path, verbose=args.verbose)
        elif fmt_name == 'hex':
            ok, msg = gen_func(elf_path, out_path, verbose=args.verbose)
        else:
            # 理论上不会到这里
            ok, msg = gen_func(elf_path, out_path, verbose=args.verbose)

        if isinstance(ok, bool) and ok:
            print(f"  [OK]  {desc:20s} -> {os.path.basename(out_path)}")
        else:
            err = msg if msg else "unknown error"
            print(f"  [WARN] {desc:20s}: {err}")

    # ============================================================
    # Step 4: 清理临时 ELF
    # ============================================================
    if temp_elf and not args.keep_elf:
        try:
            os.remove(temp_elf)
            if args.verbose:
                print(f"\n  [clean] removed temp ELF: {temp_elf}")
        except OSError:
            pass

    # ============================================================
    # 汇总
    # ============================================================
    print(f"\n[DONE] Output directory: {out_dir}")
    print(f"       Formats generated: {', '.join(fmt_list)}")
    print()

    # 提示 SoC_Config 设置
    if 'mem' in fmt_list:
        out_rel = os.path.relpath(out_dir, WORKING_DIR)
        itcm_mem = f'{out_base}_itcm.mem'
        dtcm_mem = f'{out_base}_dtcm.mem'
        print(f"  提示：在 SoC_Config.sv 中设置 DIRECT_LOAD 文件路径：")
        print(f"    `define ITCM_FILE \"{out_rel}/{itcm_mem}\"")
        print(f"    `define DTCM_FILE \"{out_rel}/{dtcm_mem}\"")

    if 'uartbin' in fmt_list:
        uartbin = f'{out_base}.uartbin'
        print(f"  提示：上板下载时直接发送 {uartbin}")


if __name__ == '__main__':
    main()
