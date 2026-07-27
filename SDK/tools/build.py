#!/usr/bin/env python3
"""
BD32 SDK 构建脚本

用法:
  python tools/build.py demos/empty    # 自动找 demos/empty/src/main.c
  python tools/build.py demos/blink    # 同上
"""
import subprocess, sys, os, struct, argparse, glob

SDK_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BSP_DIR  = os.path.join(SDK_ROOT, "bsp")
LINKER   = os.path.join(BSP_DIR, "ld", "link.ld")
STARTUP  = os.path.join(BSP_DIR, "startup", "start.S")

# xPack RISC-V 工具链 (默认编译+链接都用它；--clang 时仅 .c 编译改用 clang)
TOOLCHAIN = "D:/RISCV_Tool/xpack-riscv-none-elf-gcc-15.2.0-1/bin"
CC       = os.path.join(TOOLCHAIN, "riscv-none-elf-gcc")
OBJCOPY  = os.path.join(TOOLCHAIN, "riscv-none-elf-objcopy")
OBJDUMP  = os.path.join(TOOLCHAIN, "riscv-none-elf-objdump")

# 官方 LLVM / Clang (方案A: clang 做 rv32 .c 代码生成, 复用 xpack 的 newlib 头与 libgcc 链接)
LLVM_BIN = "D:/RISCV_Tool/llvm-22.1.8/bin"
CLANG    = os.path.join(LLVM_BIN, "clang")
XPACK_ROOT = os.path.dirname(TOOLCHAIN)                 # .../xpack-riscv-none-elf-gcc-15.2.0-1
SYSROOT    = os.path.join(XPACK_ROOT, "riscv-none-elf") # newlib 头/库 (--newlib + --clang 时用)
CFLAGS   = [
    "-march=rv32im_zicsr", "-mabi=ilp32", "-mcmodel=medlow",
    "-nostartfiles", "-ffreestanding",
    "-ffunction-sections", "-fdata-sections",
    "-msmall-data-limit=0", "-mno-relax",
    "-I", BSP_DIR
]
LDFLAGS  = [
    "-march=rv32im_zicsr", "-mabi=ilp32",
    "-nostartfiles", "-nostdlib", "-Wl,--gc-sections"
]
LIBS     = ["-lgcc"]                           # 裸金属：仅 libgcc

# Newlib-nano 构建配置（--newlib 时使用）
NEWLIB_CFLAGS = [
    "-march=rv32im_zicsr", "-mabi=ilp32", "-mcmodel=medlow",
    "-nostartfiles",
    "-ffunction-sections", "-fdata-sections",
    "-msmall-data-limit=0", "-mno-relax",
    "-I", BSP_DIR
]
NEWLIB_LDFLAGS = [
    "-march=rv32im_zicsr", "-mabi=ilp32",
    "-nostartfiles", "-specs=nano.specs", "-Wl,--gc-sections"
]
NEWLIB_LIBS = ["-lc", "-lm", "-lgcc"]

BSP_C    = ["board/init.c", "drivers/bd32_uart.c", "trap/trap_handler.c"]
NEWLIB_BSP_C = ["board/init.c", "drivers/bd32_uart.c", "trap/trap_handler.c", "porting/syscalls.c", "utils/printf_fixed.c"]
BSP_ASM  = ["startup/vector_table.S", "drivers/bd32_clint_asm.S"]

def run(cmd, desc=""):
    if desc: print(f"  [{desc}]")
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        print(f"  ERROR: {r.stderr}")
        sys.exit(1)
    return r.stdout

def compile(src_dir, out, usenewlib=False, useclang=False):
    build_dir = os.path.dirname(out)
    os.makedirs(build_dir, exist_ok=True)

    # Select config
    cflags = NEWLIB_CFLAGS if usenewlib else CFLAGS
    ldflags = NEWLIB_LDFLAGS if usenewlib else LDFLAGS
    libs = NEWLIB_LIBS if usenewlib else LIBS
    bsp_c = NEWLIB_BSP_C if usenewlib else BSP_C

    # .c 编译器选择：默认 xpack gcc；--clang 时改用官方 clang 做前端代码生成
    # (.S 启动文件与链接始终用 gcc，保证启动代码/link.ld 行为与现状完全一致)
    compiler = CLANG if useclang else CC
    clang_extra = []
    if useclang:
        clang_extra = ["--target=riscv32-unknown-elf"]
        if usenewlib:
            clang_extra += ["--sysroot=" + SYSROOT]

    # .o files go into build/
    def obj_path(name):
        return os.path.join(build_dir, name)

    def obj_name(src_path):
        """源文件路径 → .o 文件名，去掉扩展名，路径斜杠变下划线"""
        name = src_path.replace('/', '_').replace('\\', '_')
        return os.path.splitext(name)[0] + '.o'

    objs = []

    # Assemble startup (始终用 gcc 汇编 .S)
    obj = obj_path(obj_name("start"))
    run([CC] + cflags + ["-c", STARTUP, "-o", obj], "AS start.S")
    objs.append(obj)

    # Compile BSP .c
    for c in bsp_c:
        obj = obj_path(obj_name(c))
        run([compiler] + clang_extra + cflags + ["-c", os.path.join(BSP_DIR, c), "-o", obj], f"CC {c}")
        objs.append(obj)

    # Compile BSP .S (始终用 gcc 汇编 .S)
    for s in BSP_ASM:
        obj = obj_path(obj_name(s))
        run([CC] + cflags + ["-c", os.path.join(BSP_DIR, s), "-o", obj], f"AS {s}")
        objs.append(obj)

    # Compile all user sources in src_dir
    sources = sorted(glob.glob(os.path.join(src_dir, "*.c")))
    if not sources:
        print(f"ERROR: no .c files found in {src_dir}")
        sys.exit(1)
    for src in sources:
        base = os.path.basename(src)
        obj = obj_path(obj_name(base))
        run([compiler] + clang_extra + cflags + ["-c", src, "-o", obj], f"CC {base}")
        objs.append(obj)

    # Link (libs AFTER objs) — 始终用 xpack gcc (复用 link.ld + libgcc)
    run([CC] + cflags + ldflags + ["-T", LINKER] + objs + libs + ["-o", out], "LD")

    # Generate dump
    dump = obj_path("out.dump")
    stdout = run([OBJDUMP, "-d", out], "OBJDUMP")
    with open(dump, "w") as f: f.write(stdout)

    # Cleanup .o files
    for obj in objs:
        try: os.remove(obj)
        except: pass

    return out

def elf_to_bin(elf_path, itcm_base=0x00010000, itcm_size=0x4000, name_suffix=""):
    """ELF -> .uartbin + .mem。分别提取 ITCM + DTCM 段。
    name_suffix: 输出文件名后缀，如 "_o2" → coremark_o2_itcm.mem"""
    import tempfile
    base = os.path.splitext(elf_path)[0]

    def extract_section(sec_name):
        """提取单个 ELF section，返回 int 列表（0 表示不存在或为空）"""
        with tempfile.NamedTemporaryFile(suffix='.bin', delete=False) as tf:
            tmp = tf.name
        try:
            r = subprocess.run(
                [OBJCOPY, '--dump-section', f'{sec_name}={tmp}', elf_path, os.devnull],
                capture_output=True, text=True
            )
            if r.returncode != 0:
                return []
            with open(tmp, 'rb') as f:
                data = f.read()
            if len(data) == 0:
                return []
            if len(data) % 4:
                data += b'\x00' * (4 - len(data) % 4)
            return [int.from_bytes(data[i:i+4], 'little') for i in range(0, len(data), 4)]
        finally:
            try: os.remove(tmp)
            except: pass

    # ITCM: .text（含 .init + .trap.vector，链接器合入）
    itcm_words = extract_section(".text")

    # DTCM: .data + .rodata（只读数据放 DTCM，ITCM 纯代码）
    dtcm_words = extract_section(".data")
    dtcm_words.extend(extract_section(".rodata"))

    # Write .mem (for $readmemh，ITCM)
    itcm_mem_path = base + name_suffix + "_itcm.mem"
    with open(itcm_mem_path, "w") as f:
        for w in itcm_words:
            f.write(f"{w:08x}\n")
    print(f"  MEM_ITCM: {len(itcm_words)} words -> {itcm_mem_path}")

    # Write .mem (DTCM)
    dtcm_mem_path = base + name_suffix + "_dtcm.mem"
    with open(dtcm_mem_path, "w") as f:
        for w in dtcm_words:
            f.write(f"{w:08x}\n")
    print(f"  MEM_DTCM: {len(dtcm_words)} words -> {dtcm_mem_path}")

    # Write .uartbin (START_FRAME + ITCM + DTCM)
    uartbin_path = base + name_suffix + ".uartbin"
    START_FRAME = 0xBBAABBAA
    with open(uartbin_path, "wb") as f:
        f.write(struct.pack('<I', START_FRAME))
        f.write(struct.pack('<I', len(itcm_words)))
        for w in itcm_words:
            f.write(struct.pack('<I', w))
        f.write(struct.pack('<I', len(dtcm_words)))
        for w in dtcm_words:
            f.write(struct.pack('<I', w))
    print(f"  UARTBIN: {os.path.getsize(uartbin_path)} bytes "
          f"(ITCM={len(itcm_words)} DTCM={len(dtcm_words)}) -> {uartbin_path}")

    # 同步到 test_data/soc/c/（仿真用）
    import shutil
    work_root = os.path.dirname(SDK_ROOT)            # Working/
    sim_dir = os.path.join(work_root, "test_data", "soc", "c")
    os.makedirs(sim_dir, exist_ok=True)
    for sf in [uartbin_path, itcm_mem_path, dtcm_mem_path]:
        sp = os.path.join(sim_dir, os.path.basename(sf))
        shutil.copy(sf, sp)
        print(f"  SYNC: -> {sp}")

    return uartbin_path

def main():
    p = argparse.ArgumentParser(description="BD32 SDK Build Tool")
    p.add_argument("source", nargs="?", default=None, help="C source file or demo directory")
    p.add_argument("-o", "--output", default=None, help="Output ELF path")
    p.add_argument("--no-bin", action="store_true", help="Skip .mem/.uartbin")
    p.add_argument("--newlib", action="store_true", help="Link with newlib-nano (printf, malloc, etc.)")
    p.add_argument("--clang", action="store_true", help="Use LLVM/clang for .c compilation (linking still via xpack gcc)")
    p.add_argument("--opt", default="Os", help="Optimization (Os, O2, O3, etc.)")
    p.add_argument("--extra", default="", help="Extra GCC flags")
    args = p.parse_args()

    # Apply optimization override
    opt_flag = "-" + args.opt
    CFLAGS.insert(3, opt_flag)
    NEWLIB_CFLAGS.insert(2, opt_flag)
    # Extra flags
    extra_list = args.extra.split() if args.extra else []
    CFLAGS.extend(extra_list)
    NEWLIB_CFLAGS.extend(extra_list)
    # Build flags string for display
    flags_parts = ["-" + args.opt] + extra_list
    flags_str = " ".join(flags_parts)
    CFLAGS.append(f'-DFLAGS_STR="{flags_str} -march=rv32im_zicsr -mabi=ilp32"')
    NEWLIB_CFLAGS.append(f'-DFLAGS_STR="{flags_str} -march=rv32im_zicsr -mabi=ilp32"')

    if args.source is None:
        print("Usage: python tools/build.py demos/hello          # auto-detect demos/hello/src/main.c")
        print("       python tools/build.py demos/hello/main.c   # explicit source")
        sys.exit(0)

    src = os.path.abspath(args.source)
    if os.path.isdir(src):
        # Auto: demos/hello → demos/hello/src/  (compile all .c files)
        src_dir = os.path.join(src, "src")
        if not os.path.isdir(src_dir):
            print(f"ERROR: No src/ directory in {args.source}")
            sys.exit(1)
        demo_dir = src
        name = os.path.basename(src)
    else:
        # Explicit source file: demos/hello/main.c
        src_dir = os.path.dirname(src)
        demo_dir = os.path.dirname(os.path.dirname(src))
        name = os.path.basename(demo_dir)

    if args.output is None:
        # 按优化等级和编译器命名 build 文件夹：build_O2, build_clang_O3, etc.
        if args.clang:
            build_subdir = f"build_clang_{args.opt}"
            name_suffix = f"_clang_{args.opt.lower()}"
        else:
            build_subdir = f"build_{args.opt}"
            name_suffix = f"_{args.opt.lower()}"
        args.output = os.path.join(demo_dir, build_subdir, name + ".elf")
    else:
        name_suffix = ""

    args.output = os.path.abspath(args.output)

    print(f"BD32 SDK Build: {src_dir} -> {args.output}")
    compile(src_dir, args.output, usenewlib=args.newlib, useclang=args.clang)

    if not args.no_bin:
        elf_to_bin(args.output, name_suffix=name_suffix)

    print(f"OK: {args.output}")

if __name__ == "__main__":
    main()
