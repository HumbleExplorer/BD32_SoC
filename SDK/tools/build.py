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
TOOLCHAIN = os.environ.get("RISCV_TOOLCHAIN", "D:/RISCV_Tool/xpack-riscv-none-elf-gcc-15.2.0-1/bin")
CC       = os.path.join(TOOLCHAIN, "riscv-none-elf-gcc")
OBJCOPY  = os.path.join(TOOLCHAIN, "riscv-none-elf-objcopy")
OBJDUMP  = os.path.join(TOOLCHAIN, "riscv-none-elf-objdump")

# 官方 LLVM / Clang (方案A: clang 做 rv32 .c 代码生成, 复用 xpack 的 newlib 头与 libgcc 链接)
LLVM_BIN = os.environ.get("LLVM_BIN", "D:/RISCV_Tool/llvm-22.1.8/bin")
CLANG    = os.path.join(LLVM_BIN, "clang")
LDLLD    = os.path.join(LLVM_BIN, "ld.lld")     # --lld 链接器（支持 LTO + ICF）
XPACK_ROOT = os.path.dirname(TOOLCHAIN)                 # .../xpack-riscv-none-elf-gcc-15.2.0-1
SYSROOT    = os.path.join(XPACK_ROOT, "riscv-none-elf") # newlib 头/库 (--newlib + --clang 时用)
# LLD 链接用库目录（newlib-nano + libgcc，rv32im/ilp32）
LIBC_DIR = os.path.join(SYSROOT, "lib", "rv32im", "ilp32")
LIBGCC_DIR = next((d for d in glob.glob(os.path.join(
    XPACK_ROOT, "lib", "gcc", "riscv-none-elf", "*", "rv32im", "ilp32"))
    if os.path.exists(os.path.join(d, "libgcc.a"))), None)

def get_picolibc_dirs(variant):
    """picolibc 安装目录。variant ∈ {i, f, d}（printf 档位，由
    build_picolibc.bat 构建：i → picolibc-install，f/d → picolibc-install-<v>）。
    环境变量 PICOLIBC_ROOT 优先（此时忽略 variant）。"""
    env = os.environ.get("PICOLIBC_ROOT")
    if env:
        root = env
    else:
        base = os.path.join(os.path.dirname(SDK_ROOT), "third_party")
        root = os.path.join(base,
            "picolibc-install" if variant == "i" else f"picolibc-install-{variant}")
    return (os.path.join(root, "include"),
            os.path.join(root, "lib", "rv32im", "ilp32"))
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

# ============ RT-Thread 模式（--rtthread [--rtthread-version]） ============
# 内核取自 third_party/rt-thread-3.1.5（lts-v3.1.x，默认）或
# third_party/rt-thread-5.1.0（只读），BSP 移植文件在 bsp/rtthread 或
# bsp/rtthread51（BD32 适配文件跟随仓库）。
def get_rtt_config(version):
    """返回 (RTT_ROOT, RTT_INC, RTT_KERNEL_SRC, RTT_LIBCPU_C, RTT_BSP_ASM)"""
    if version == "315":
        root = os.path.join(os.path.dirname(SDK_ROOT), "third_party", "rt-thread-3.1.5")
        inc = [
            os.path.join(root, "include"),
            os.path.join(root, "include", "libc"),
            os.path.join(BSP_DIR, "rtthread"),
        ]
        # 单核所需内核源（v3.1.5 为单文件 scheduler.c；无 src/klibc）
        kern = ["clock.c", "components.c", "cpu.c", "idle.c", "ipc.c", "irq.c",
                "kservice.c", "mem.c", "object.c",
                "scheduler.c", "thread.c", "timer.c"]
        kern_c = [os.path.join(root, "src", f) for f in kern]
        # BD32 适配的 3.1.5 libcpu + 中断入口（bsp/rtthread，随仓库跟踪）
        libcpu_c = [os.path.join(BSP_DIR, "rtthread", "cpuport.c")]
        bsp_asm = [
            os.path.join(BSP_DIR, "rtthread", "rt_trap.S"),
            os.path.join(BSP_DIR, "rtthread", "context_gcc.S"),
            os.path.join(BSP_DIR, "rtthread", "interrupt_gcc.S"),
        ]
    else:  # "51"
        root = os.path.join(os.path.dirname(SDK_ROOT), "third_party", "rt-thread-5.1.0")
        inc = [
            os.path.join(root, "include"),
            os.path.join(root, "include", "libc"),
            os.path.join(root, "libcpu", "risc-v", "common"),
            os.path.join(BSP_DIR, "rtthread51"),
        ]
        # 单核所需内核源（v5.1.0，SMP 专用 scheduler_mp 不编）
        kern = ["clock.c", "components.c", "cpu.c", "idle.c", "ipc.c", "irq.c",
                "kservice.c", "mem.c", "object.c",
                "scheduler_comm.c", "scheduler_up.c", "thread.c", "timer.c"]
        # src/klibc：字符串/格式化（v5.1 的 rt_vsnprintf 在 kstdio.c）
        kern += ["klibc/kstdio.c", "klibc/kstring.c"]
        kern_c = [os.path.join(root, "src", f) for f in kern]
        # 官方 v5.1 libcpu cpuport.c
        libcpu_c = [os.path.join(root, "libcpu", "risc-v", "common", "cpuport.c")]
        bsp_asm = [
            os.path.join(BSP_DIR, "rtthread51", "rt_trap.S"),
            os.path.join(root, "libcpu", "risc-v", "common", "context_gcc.S"),
            os.path.join(root, "libcpu", "risc-v", "common", "interrupt_gcc.S"),
        ]
    return root, inc, kern_c, libcpu_c, bsp_asm

def run(cmd, desc=""):
    if desc: print(f"  [{desc}]")
    r = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", errors="replace")
    if r.returncode != 0:
        print(f"  ERROR: {r.stderr}")
        sys.exit(1)
    return r.stdout

def sanitize_ld_flags(flags):
    """把 GCC 驱动风格链接参数(-Wl,a,b)转成 lld 直接可用的参数。
    非 -Wl 前缀参数原样透传(如 -flto 本身 lld 也接受)。"""
    out = []
    for f in (flags or []):
        if f.startswith("-Wl,"):
            out.extend(f[4:].split(","))
        else:
            out.append(f)
    return out

def compile(src_dir, out, usenewlib=False, useclang=False, usertt=False, rtt_ver="315",
            irq_mode="ch32", clang_extra_flags=None, ld_extra_flags=None, uselld=False,
            usepicolibc=False, picolibc_printf="i"):
    build_dir = os.path.dirname(out)
    os.makedirs(build_dir, exist_ok=True)

    # Select config
    if usertt:
        rtt_root, rtt_inc, rtt_kern_c, rtt_libcpu_c, rtt_bsp_asm = get_rtt_config(rtt_ver)
        rtt_cflags = ["-DRT_USING_RTTHREAD"] + ["-I" + p for p in rtt_inc]
        if irq_mode == "unified":
            # 统一入口：3/7/11 全部全量保存 + 中断返回直接切换（无软件中断依赖）
            rtt_cflags.append("-DRT_USING_UNIFIED_IRQ")
        if rtt_ver == "315":
            rtt_bsp_c = NEWLIB_BSP_C + ["rtthread/board.c"]
        else:
            rtt_bsp_c = NEWLIB_BSP_C + ["rtthread51/board.c"]
        cflags = NEWLIB_CFLAGS + rtt_cflags
        ldflags = NEWLIB_LDFLAGS
        libs = NEWLIB_LIBS
        bsp_c = rtt_bsp_c
        bsp_asm = rtt_bsp_asm
    else:
        if usepicolibc:
            picolibc_inc_dir, picolibc_libdir = get_picolibc_dirs(picolibc_printf)
            picolibc_inc = ["-I", picolibc_inc_dir]
            if not os.path.exists(os.path.join(picolibc_inc_dir, "stdio.h")):
                print("ERROR: picolibc 未构建。请先运行 SDK/tools/build_picolibc.bat，"
                      f"或用环境变量 PICOLIBC_ROOT 指向已安装的 picolibc（当前变体: {picolibc_printf}）。")
                sys.exit(1)
            cflags = NEWLIB_CFLAGS + ["-ffreestanding"] + picolibc_inc
            ldflags = LDFLAGS          # 裸金属链接参数，无 -specs=nano.specs
            libs = ["-L", picolibc_libdir, "-lc", "-lm", "-lgcc"]
            # picolibc 模式：syscalls 换 picolibc 版（sbrk 而非 _sbrk），
            # 新增 console FILE 适配；printf_fixed（自定义 print_fixed）保留
            bsp_c = ["board/init.c", "drivers/bd32_uart.c", "trap/trap_handler.c",
                     "porting/picolibc_syscalls.c", "porting/picolibc_console.c",
                     "utils/printf_fixed.c"]
            bsp_asm = BSP_ASM
        else:
            cflags = NEWLIB_CFLAGS if usenewlib else CFLAGS
            ldflags = NEWLIB_LDFLAGS if usenewlib else LDFLAGS
            libs = NEWLIB_LIBS if usenewlib else LIBS
            bsp_c = NEWLIB_BSP_C if usenewlib else BSP_C
            bsp_asm = BSP_ASM

    # 链接器专属参数（--ld-extra，如 -Wl,--icf=all / -flto）
    if ld_extra_flags:
        ldflags = ldflags + ld_extra_flags

    # --lld：clang .c 编译启用 LTO（LLD 消费 LLVM bitcode）
    if uselld and useclang:
        clang_extra_flags = (clang_extra_flags or []) + ["-flto"]

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
        cc_extra = clang_extra + (clang_extra_flags or []) if useclang else []
        run([compiler] + cc_extra + cflags + ["-c", os.path.join(BSP_DIR, c), "-o", obj], f"CC {c}")
        objs.append(obj)

    # Compile BSP .S (始终用 gcc 汇编 .S)
    for s in bsp_asm:
        s_full = s if os.path.isabs(s) else os.path.join(BSP_DIR, s)
        obj = obj_path(obj_name(s))
        run([CC] + cflags + ["-c", s_full, "-o", obj], f"AS {s}")
        objs.append(obj)

    # RT-Thread 内核 + libcpu
    if usertt:
        # 内核源码需要 __RT_KERNEL_SOURCE__ 才能看到 rtsched.h 的内部 API
        rtt_kernel_cflags = cflags + ["-D__RT_KERNEL_SOURCE__"]
        rtt_cc_extra = clang_extra + (clang_extra_flags or []) if useclang else []
        for c in rtt_kern_c:
            obj = obj_path(obj_name(c))
            run([compiler] + rtt_cc_extra + rtt_kernel_cflags + ["-c", c, "-o", obj], f"CC rt-thread/{os.path.basename(c)}")
            objs.append(obj)
        for c in rtt_libcpu_c:
            obj = obj_path(obj_name(c))
            run([compiler] + rtt_cc_extra + rtt_kernel_cflags + ["-c", c, "-o", obj], f"CC rt-thread/{os.path.basename(c)}")
            objs.append(obj)

    # Compile all user sources in src_dir
    sources = sorted(glob.glob(os.path.join(src_dir, "*.c")))
    if not sources:
        print(f"ERROR: no .c files found in {src_dir}")
        sys.exit(1)
    for src in sources:
        base = os.path.basename(src)
        obj = obj_path(obj_name(base))
        cc_extra = clang_extra + (clang_extra_flags or []) if useclang else []
        run([compiler] + cc_extra + cflags + ["-c", src, "-o", obj], f"CC {base}")
        objs.append(obj)

    # Link — 默认 xpack gcc；--lld 用 LLVM LLD（--gc-sections + --icf=all）
    if uselld:
        if usepicolibc:
            lld_libs = ["-L", picolibc_libdir, "-lc", "-lm",
                        "-L", LIBGCC_DIR, "-lgcc"]
        elif usenewlib or usertt:
            lld_libs = ["-L", LIBC_DIR, "-L", LIBGCC_DIR, "-lc_nano", "-lm_nano", "-lgcc"]
        else:
            lld_libs = ["-L", LIBGCC_DIR, "-lgcc"]
        run([LDLLD, "-m", "elf32lriscv", "-T", LINKER] + objs + lld_libs +
            ["--gc-sections", "--icf=all"] + sanitize_ld_flags(ld_extra_flags) +
            ["-o", out], "LD (lld)")
    else:
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
    p.add_argument("--debug", action="store_true", help="Compile with -g (GDB source-level debug info)")
    p.add_argument("--newlib", action="store_true", help="Link with newlib-nano (printf, malloc, etc.)")
    p.add_argument("--picolibc", action="store_true",
                   help="Link with picolibc（体积更小的 C 库；需先运行 build_picolibc.bat 构建）")
    p.add_argument("--picolibc-printf", default="i", choices=["i", "f", "d"],
                   help="picolibc printf 档位：i=整数（默认，最小）/ f=浮点 / d=double（需对应档位已构建）")
    p.add_argument("--rtthread", action="store_true", help="Build with RT-Thread kernel (bsp/rtthread + third_party/rt-thread)")
    p.add_argument("--rtthread-version", default="315", choices=["51", "315"],
                   help="RT-Thread kernel version: 315 (lts-v3.1.x, default) or 51 (v5.1.0)")
    p.add_argument("--irq-mode", default="ch32", choices=["ch32", "unified"],
                   help="RT-Thread 中断模式: ch32 (轻量入口 + 软件中断延迟切换, default) or unified (统一入口, 全量保存 + 直接切换)")
    p.add_argument("--clang", action="store_true", help="Use LLVM/clang for .c compilation (linking still via xpack gcc)")
    p.add_argument("--opt", default="Os", help="Optimization (Os, O2, O3, etc.)")
    p.add_argument("--extra", default="", help="Extra GCC flags")
    p.add_argument("--clang-extra", default="",
                   help="Extra flags for clang .c compilation only (e.g. \"-mllvm -enable-machine-outliner=0\")")
    p.add_argument("--ld-extra", default="",
                   help="Extra flags for link only (e.g. \"-Wl,--icf=all\" or \"-flto\")")
    p.add_argument("--lld", action="store_true",
                   help="用 LLVM LLD 链接（ICF 折叠相同代码；配合 --clang 额外启用 LTO，体积更小）")
    args = p.parse_args()

    if args.picolibc and (args.newlib or args.rtthread):
        print("ERROR: --picolibc 与 --newlib/--rtthread 互斥（RT-Thread 依赖 newlib-nano 的 libc 接口）")
        sys.exit(1)

    # Apply optimization override
    opt_flag = "-" + args.opt
    CFLAGS.insert(3, opt_flag)
    NEWLIB_CFLAGS.insert(2, opt_flag)
    # GDB source-level debug info (--debug)
    if args.debug:
        CFLAGS.append("-g")
        NEWLIB_CFLAGS.append("-g")
    # Extra flags
    extra_list = args.extra.split() if args.extra else []
    CFLAGS.extend(extra_list)
    NEWLIB_CFLAGS.extend(extra_list)
    clang_extra_list = args.clang_extra.split() if args.clang_extra else []
    ld_extra_list = args.ld_extra.split() if args.ld_extra else []
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
        lld_tag = "_lld" if args.lld else ""
        if args.picolibc:
            if args.clang:
                build_subdir = f"build_picolibc_clang{lld_tag}_{args.opt}"
                name_suffix = f"_picolibc_clang{lld_tag}_{args.opt.lower()}"
            else:
                build_subdir = f"build_picolibc{lld_tag}_{args.opt}"
                name_suffix = f"_picolibc{lld_tag}_{args.opt.lower()}"
        elif args.clang:
            build_subdir = f"build_clang{lld_tag}_{args.opt}"
            name_suffix = f"_clang{lld_tag}_{args.opt.lower()}"
        else:
            build_subdir = f"build{lld_tag}_{args.opt}"
            name_suffix = f"{lld_tag}_{args.opt.lower()}"
        args.output = os.path.join(demo_dir, build_subdir, name + ".elf")
    else:
        name_suffix = ""

    args.output = os.path.abspath(args.output)

    # --debug：link.ld 的 /DISCARD/ 会丢弃 .debug*，生成去掉该规则的脚本以保留 GDB 调试信息
    if args.debug:
        global LINKER
        with open(LINKER, encoding="utf-8") as _f:
            _ld = _f.read().replace("*(.debug*)", "")
        _dbg_ld = os.path.join(os.path.dirname(args.output), "link_debug.ld")
        with open(_dbg_ld, "w", encoding="utf-8") as _f:
            _f.write(_ld)
        LINKER = _dbg_ld

    print(f"BD32 SDK Build: {src_dir} -> {args.output}")
    compile(src_dir, args.output, usenewlib=(args.newlib or args.rtthread),
            useclang=args.clang, usertt=args.rtthread, rtt_ver=args.rtthread_version,
            irq_mode=args.irq_mode, clang_extra_flags=clang_extra_list,
            ld_extra_flags=ld_extra_list, uselld=args.lld, usepicolibc=args.picolibc,
            picolibc_printf=args.picolibc_printf)

    if not args.no_bin:
        elf_to_bin(args.output, name_suffix=name_suffix)

    print(f"OK: {args.output}")

if __name__ == "__main__":
    main()
