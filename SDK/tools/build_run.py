#!/usr/bin/env python3
"""
BD32 一键构建 + 上板运行

一条命令完成：构建固件（build.py）→ 复位 FPGA（fpga_reset.py）→
UART 下载（uart_send.py）→ 监听运行输出。

用法（在 SDK/ 目录下执行）：
    python tools/build_run.py demos/newlib/hello --newlib
    python tools/build_run.py demos/rtthread --rtthread --idle-timeout 5
    python tools/build_run.py demos/nolibc/breathing --no-listen      # 只下载，不监听
    python tools/build_run.py demos/rtthread --rtthread --irq-mode unified --no-reset

构建参数透传 build.py，运行参数透传 uart_send.py；产物命名与 build.py 一致
（默认 Os → <demo>_os.uartbin；--opt O2 → <demo>_o2.uartbin；--clang → <demo>_clang_<opt>.uartbin）。
"""
import argparse
import os
import subprocess
import sys

SDK_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BUILD_PY = os.path.join(SDK_ROOT, "tools", "build.py")
UART_SEND_PY = os.path.join(SDK_ROOT, "tools", "uart_send.py")


def main():
    p = argparse.ArgumentParser(
        description="BD32 一键构建 + 上板运行（构建 → 复位 → 下载 → 监听）")
    p.add_argument("demo", help="demo 目录（如 demos/rtthread）")

    # ---- 构建参数（透传 build.py）----
    p.add_argument("--newlib", action="store_true", help="链接 newlib-nano")
    p.add_argument("--clang", action="store_true", help="用 Clang 前端编译")
    p.add_argument("--rtthread", action="store_true", help="RT-Thread 模式")
    p.add_argument("--rtthread-version", default=None, choices=["51", "315"],
                   help="RT-Thread 内核版本（默认 315 = lts-v3.1.x）")
    p.add_argument("--irq-mode", default=None, choices=["ch32", "unified"],
                   help="RT-Thread 中断模式（默认 ch32）")
    p.add_argument("--opt", default=None, help="优化等级（默认 Os）")
    p.add_argument("--debug", action="store_true", help="启用 -g 调试信息")
    p.add_argument("--extra", default=None, help="追加编译标志")

    # ---- 运行参数（透传 uart_send.py）----
    p.add_argument("--port", default=None, help="COM 口（默认自动检测 CH340）")
    p.add_argument("--baud", type=int, default=None, help="波特率（默认 115200）")
    p.add_argument("--idle-timeout", type=float, default=3.0,
                   help="下载后监听：连续 N 秒无数据即停（默认 3s；--no-listen 关闭）")
    p.add_argument("--timeout", type=float, default=None, help="监听总时长上限")
    p.add_argument("--until", default=None, help="精确结束标记（命中后停在标记末尾）")
    p.add_argument("--log", default=None, help="监听日志文件路径")
    p.add_argument("--no-reset", action="store_true", help="下载前不复位 FPGA")
    p.add_argument("--no-listen", action="store_true", help="下载后不监听输出")
    args = p.parse_args()

    # 1) 构建
    build_cmd = [sys.executable, BUILD_PY, args.demo]
    for flag in ("--newlib", "--clang", "--rtthread", "--debug"):
        if getattr(args, flag.lstrip("-").replace("-", "_")):
            build_cmd.append(flag)
    for flag, val in (("--rtthread-version", args.rtthread_version),
                      ("--irq-mode", args.irq_mode),
                      ("--opt", args.opt),
                      ("--extra", args.extra)):
        if val:
            build_cmd += [flag, str(val)]
    print(f"[1/2] Building {args.demo} ...")
    r = subprocess.run(build_cmd)
    if r.returncode != 0:
        sys.exit(r.returncode)

    # 2) 定位 uartbin（命名规则与 build.py 一致，产物已同步到 test_data/soc/c/）
    name = os.path.basename(os.path.normpath(args.demo))
    opt = (args.opt or "Os").lower()
    if args.clang:
        suffix = f"_clang_{opt}"
    else:
        suffix = f"_{opt}"
    uartbin = os.path.normpath(os.path.join(
        SDK_ROOT, "..", "test_data", "soc", "c", name + suffix + ".uartbin"))
    if not os.path.exists(uartbin):
        print(f"[ERROR] 未找到构建产物: {uartbin}")
        sys.exit(1)
    print(f"[1/2] uartbin: {uartbin}")

    # 3) 复位 + 下载 + 监听
    run_cmd = [sys.executable, UART_SEND_PY, uartbin]
    if args.port:
        run_cmd += ["--port", args.port]
    if args.baud:
        run_cmd += ["--baud", str(args.baud)]
    if not args.no_reset:
        run_cmd.append("--reset")
    if not args.no_listen:
        run_cmd += ["--idle-timeout", str(args.idle_timeout)]
    if args.timeout:
        run_cmd += ["--timeout", str(args.timeout)]
    if args.until:
        run_cmd += ["--until", args.until]
    if args.log:
        run_cmd += ["--log", args.log]
    print(f"[2/2] Download & run: {os.path.basename(uartbin)}")
    sys.exit(subprocess.run(run_cmd).returncode)


if __name__ == "__main__":
    main()
