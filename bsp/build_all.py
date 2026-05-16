#!/usr/bin/env python3
"""
BD32 SoC 统一构建工具

编译 → 生成 .elf / .uartbin / .mem(ITCM/DTCM for $readmemh)

用法:
  # 完整流程：编译 + .uartbin + .mem(ITCM+DTCM)
  python bsp/build_all.py src/demos/step2_irq_pwm/main.c -o test_data/custom/step2

  # 仅从已有 .elf 提取 .mem (跳过编译)
  python bsp/build_all.py --elf /path/to/out.elf --extract-mem

  # 仅生成 .uartbin (从已有 .elf)
  python bsp/build_all.py --elf /path/to/out.elf --make-uartbin -o test.uartbin
"""

import sys, os, subprocess, tempfile, struct, shutil, re

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
WORKING_DIR = os.path.dirname(SCRIPT_DIR)  # Working/
PREFIX = "riscv64-unknown-elf-"
CC = PREFIX + "gcc"
LD = PREFIX + "gcc"
OBJCOPY = PREFIX + "objcopy"
OBJDUMP = PREFIX + "objdump"
START_FRAME = 0xBBAABBAA

BSP_CORE_FILES = [
    "bsp/start.S", "bsp/init.c", "bsp/vector_table.S",
    "bsp/trap_handler.c", "bsp/syscalls.c",
    "bsp/bd32_uart.c", "bsp/bd32_clint_asm.S",
]


def run(cmd, desc="run"):
    """执行命令，失败时退出"""
    r = subprocess.run(cmd, capture_output=True, text=True)
    return r


def short(abspath):
    """返回相对 Working/ 的短路径"""
    try:
        return os.path.relpath(abspath, WORKING_DIR)
    except:
        return abspath


# ======================== 编译 ========================
def compile_all(src_path, build_dir, defines=None):
    """编译 BSP core + 用户程序 → .elf"""
    objs = []
    # BSP core
    for s in BSP_CORE_FILES:
        sp = os.path.join(WORKING_DIR, s)
        if not os.path.exists(sp):
            continue
        base = os.path.splitext(os.path.basename(sp))[0]
        obj = os.path.join(build_dir, base + ".o")
        if sp.endswith((".s", ".S")):
            cmd = [CC, "-c", "-march=rv32im", "-mabi=ilp32", "-o", obj, sp]
        else:
            cmd = [CC, "-c", "-Os", "-march=rv32im", "-mabi=ilp32",
                   "-fno-lto", "-fno-builtin", "-I", os.path.join(WORKING_DIR, "bsp"),
                   "-o", obj, sp]
        r = run(cmd)
        if r.returncode != 0:
            print(f"ERROR {s}:", r.stderr, file=sys.stderr); sys.exit(1)
        print(f"  CC {s}")
        objs.append(obj)

    # 用户程序
    base = os.path.splitext(os.path.basename(src_path))[0]
    obj = os.path.join(build_dir, base + ".o")
    if src_path.endswith((".s", ".S")):
        cmd = [CC, "-c", "-march=rv32im", "-mabi=ilp32",
               "-I", os.path.join(WORKING_DIR, "bsp"), "-o", obj, src_path]
    else:
        cmd = [CC, "-c", "-Os", "-march=rv32im", "-mabi=ilp32",
               "-fno-lto", "-fno-builtin",
               "-I", os.path.join(WORKING_DIR, "bsp"),
               "-o", obj, src_path]
    if defines:
        for d in defines:
            cmd.append(f"-D{d}")
    r = run(cmd)
    if r.returncode != 0:
        print(f"ERROR {src_path}:", r.stderr, file=sys.stderr); sys.exit(1)
    print(f"  CC {short(src_path)}")
    objs.append(obj)

    # 链接
    elf = os.path.join(build_dir, "output.elf")
    ldscript = os.path.join(WORKING_DIR, "bsp", "link.ld")
    cmd = [LD, "-march=rv32im", "-mabi=ilp32",
           "-nostartfiles", "-nodefaultlibs",
           "-T", ldscript, "-o", elf] + objs
    r = run(cmd)
    if r.returncode != 0:
        print(f"ERROR link:", r.stderr, file=sys.stderr); sys.exit(1)
    print(f"  LD output.elf")
    return elf


# ======================== 提取 .mem ========================
def dump_section_words(elf_path, section_name):
    """用 objcopy dump 某 section，返回 32 位小端字列表"""
    tmp = tempfile.NamedTemporaryFile(suffix='.bin', delete=False)
    tmp.close()
    r = run([OBJCOPY, '--dump-section', f'{section_name}={tmp.name}',
             elf_path, os.devnull])
    if r.returncode != 0:
        os.remove(tmp.name)
        return None
    with open(tmp.name, 'rb') as f:
        data = f.read()
    os.remove(tmp.name)
    if not data:
        return []
    if len(data) % 4:
        data += b'\x00' * (4 - len(data) % 4)
    return [struct.unpack('<I', data[i:i+4])[0] for i in range(0, len(data), 4)]


def extract_mem(elf_path, output_prefix):
    """从 .elf 提取 ITCM(.text区) 和 DTCM(.data/.rodata) → .mem"""
    # ITCM: 所有代码段
    itcm_sections = ['.reset', '.trap.vector', '.init', '.text',
                     '.trap.handler', '.vector_table', '.riscv.jvt']
    itcm_words = []
    for sec in itcm_sections:
        ws = dump_section_words(elf_path, sec)
        if ws is not None and ws:
            print(f"  ITCM {sec}: {len(ws)} words")
            itcm_words.extend(ws)

    # DTCM: 数据段
    dtcm_sections = ['.rodata', '.data', '.sdata', '.bss']
    dtcm_words = []
    for sec in dtcm_sections:
        ws = dump_section_words(elf_path, sec)
        if ws is not None and ws:
            print(f"  DTCM {sec}: {len(ws)} words")
            dtcm_words.extend(ws)

    # 写 .mem 文件
    if itcm_words:
        p = f"{output_prefix}_itcm.mem"
        with open(p, 'w') as f:
            for w in itcm_words:
                f.write(f"{w:08X}\n")
        print(f"  -> {p} ({len(itcm_words)} words)")
    else:
        print("  WARNING: no ITCM words found")

    if dtcm_words:
        p = f"{output_prefix}_dtcm.mem"
        with open(p, 'w') as f:
            for w in dtcm_words:
                f.write(f"{w:08X}\n")
        print(f"  -> {p} ({len(dtcm_words)} words)")
    else:
        print("  (DTCM empty)")

    return itcm_words, dtcm_words


# ======================== 生成 .uartbin ========================
def make_uartbin(elf_path, output_path):
    """从 .elf 打包 .uartbin（与 build.py 一致）"""
    itcm_sections = ['.reset', '.trap.vector', '.init', '.text',
                     '.trap.handler', '.vector_table', '.riscv.jvt']
    dtcm_sections = ['.rodata', '.data', '.sdata']
    itcm_words = []
    dtcm_words = []

    for sec in itcm_sections:
        ws = dump_section_words(elf_path, sec)
        if ws:
            print(f"  ITCM {sec}: {len(ws)} words")
            itcm_words.extend(ws)

    for sec in dtcm_sections:
        ws = dump_section_words(elf_path, sec)
        if ws:
            print(f"  DTCM {sec}: {len(ws)} words")
            dtcm_words.extend(ws)

    if not itcm_words:
        print("ERROR: no ITCM data", file=sys.stderr)
        sys.exit(1)

    with open(output_path, 'wb') as f:
        f.write(struct.pack('<I', START_FRAME))
        f.write(struct.pack('<I', len(itcm_words)))
        for w in itcm_words:
            f.write(struct.pack('<I', w))
        f.write(struct.pack('<I', len(dtcm_words)))
        for w in dtcm_words:
            f.write(struct.pack('<I', w))

    fs = os.path.getsize(output_path)
    print(f"\n  ITCM: {len(itcm_words)} words, DTCM: {len(dtcm_words)} words")
    print(f"  Output: {output_path} ({fs} bytes)")


# ======================== 入口 ========================
def main():
    import argparse
    ap = argparse.ArgumentParser(description="BD32 统一构建工具")
    ap.add_argument("source", nargs="?", default=None,
                    help="C/asm 源文件路径")
    ap.add_argument("--elf", default=None,
                    help="使用已有的 .elf（跳过编译）")
    ap.add_argument("-o", "--output", default=None,
                    help="输出路径前缀或完整路径")
    ap.add_argument("-D", "--define", action="append", default=[],
                    help="编译器 define")
    ap.add_argument("--make-uartbin", action="store_true",
                    help="仅生成 .uartbin（需要 --elf）")
    ap.add_argument("--extract-mem", action="store_true",
                    help="提取 ITCM+DTCM .mem 文件")
    ap.add_argument("--all", action="store_true",
                    help="编译 + uartbin + .mem 全流程")
    ap.add_argument("--disasm", action="store_true",
                    help="反汇编 .elf (带行号)")
    args = ap.parse_args()

    # ── 确定操作模式 ──
    build_elf = args.elf is not None
    extract = args.extract_mem or args.all
    make_bin = args.make_uartbin or (args.all and args.output is not None)
    do_disasm = args.disasm or args.all
    compile_src = (args.source is not None) and (not build_elf)

    if not (compile_src or build_elf or extract or make_bin or do_disasm):
        print("No action specified. Use -h for help.")
        sys.exit(1)

    if args.source:
        src_path = os.path.abspath(args.source)

    # ── 输出路径 ──
    if args.output:
        out = os.path.abspath(args.output)
        out_base, out_ext = os.path.splitext(out)
        if out_ext:  # 给了完整文件名
            # .uartbin: out_path, .mem: out_base
            uartbin_path = out
            mem_prefix = out_base
        else:        # 只有前缀
            uartbin_path = out + ".uartbin"
            mem_prefix = out
    else:
        if args.source:
            dft = os.path.splitext(os.path.basename(args.source))[0]
            uartbin_path = os.path.join(WORKING_DIR, "test_data", "custom", dft + ".uartbin")
            mem_prefix = os.path.join(WORKING_DIR, "test_data", "custom", dft)
        else:
            uartbin_path = "output.uartbin"
            mem_prefix = "output"

    # ── 编译 ──
    if compile_src:
        print("=== Compile ===")
        build_dir = tempfile.mkdtemp()
        elf_path = compile_all(src_path, build_dir, args.define)
    else:
        elf_path = os.path.abspath(args.elf) if args.elf else None
        build_dir = None

    # ── 提取 .mem ──
    if extract and elf_path:
        print("=== Extract .mem ===")
        extract_mem(elf_path, mem_prefix)

    # ── 生成 .uartbin ──
    if make_bin and elf_path:
        print("=== Make .uartbin ===")
        make_uartbin(elf_path, uartbin_path)

    # ── 反汇编 ──
    if do_disasm and elf_path:
        print("\n=== Disassembly ===")
        r = run([OBJDUMP, "-d", "-S", elf_path])
        disasm_text = r.stdout
        # 只显示 main 和关键函数的前几行
        print(disasm_text)
        # 同时存文件
        disasm_path = mem_prefix + "_disasm.txt"
        with open(disasm_path, 'w') as f:
            f.write(disasm_text)
        print(f"  Full disasm saved: {disasm_path}")

    # ── 引用信息 ──
    if make_bin and extract:
        print(f"\nDIRECT_LOAD 配置参考:")
        print(f"  MROM_FILE  = custom/mrom_jump_itcm.mem")
        print(f"  ITCM_FILE  = {os.path.basename(mem_prefix + '_itcm.mem')}")
        print(f"  DTCM_FILE  = {os.path.basename(mem_prefix + '_dtcm.mem')}")

    # 清理
    if build_dir:
        shutil.rmtree(build_dir, ignore_errors=True)


if __name__ == '__main__':
    main()
