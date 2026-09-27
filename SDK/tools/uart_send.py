"""
UART 工具 — 程序烧录 + 实时串口终端（两种模式均实时打印输出）

1. 下载模式（默认）：发送 .uartbin 到 FPGA，可先复位；下载后在同一会话
   监听输出，边收边实时打印，日志完整落盘。
2. 交互终端模式（--interactive）：打开串口后实时回显板子输出，键盘输入
   实时转发到 TX 并本地回显（--no-echo 关闭），Ctrl+C 退出。

用法：
    python tools/uart_send.py <file.uartbin>              # 自动检测串口
    python tools/uart_send.py coremark_o2.uartbin --port COM8 --baud 115200
    python tools/uart_send.py coremark_o2.uartbin --reset   # 先复位再下载
    python tools/uart_send.py uart_echo.uartbin --reset --idle-timeout 3   # 下载后监听，实时打印，输出空闲 3s 停止
    python tools/uart_send.py coremark_o2.uartbin --reset --until "Correct operation validated."
    # 长静默应用（CoreMark 类）建议 --idle-timeout 30 --timeout 300；监听期 0 字节超 6s
    # 打印一次挂死/不匹配诊断（--early-warn N 调阈值，0 关闭），结束时仍 0 字节则给明确诊断
    python tools/uart_send.py --interactive --port COM8    # 交互终端：实时收发，本地回显开，Ctrl+C 退出
    # 监听输出默认自动写入 logs/uart_send_<程序>_<时间戳>.log，可用 --log 指定路径
"""
import serial
import serial.tools.list_ports
import time
import argparse
import os
import sys
import codecs

# Windows 控制台（GBK）无法打印原始字节解码出的替换字符时避免崩溃
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")
import subprocess


def safe_log_path(user_path, root):
    """--log 路径安全校验：规范化后必须落在 root 子树内，拒绝 ../ 逃逸"""
    root = os.path.realpath(root)
    target = os.path.realpath(user_path)
    if target == root or target.startswith(root + os.sep):
        return target
    print(f"[ERROR] 日志路径越出允许目录 {root}：{user_path}")
    sys.exit(1)


def repo_root():
    # SDK/tools/uart_send.py → Working/
    return os.path.realpath(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))


def is_inside_repo(path, root=None):
    """非致命子树判定：path 规范化后是否落在 root（默认仓库根）内。
    供写文件前做纵深防御（args.log 已在入口经 safe_log_path 致命校验；
    此处再兜底一次，防止未来重构让 log_path 逃出仓库时把日志写到任意位置）。"""
    if root is None:
        root = repo_root()
    p = os.path.realpath(path)
    r = os.path.realpath(root)
    return p == r or p.startswith(r + os.sep)


def find_port():
    """自动检测 CH340 USB-UART 串口"""
    candidates = []
    for p in serial.tools.list_ports.comports():
        desc = (p.description or "").upper()
        vid_pid = f"{p.vid:04X}:{p.pid:04X}" if p.vid else ""
        # CH340: VID=1A86, PID=7523
        if "CH340" in desc or vid_pid == "1A86:7523":
            candidates.append(p.device)
    if len(candidates) == 1:
        return candidates[0]
    elif len(candidates) > 1:
        print(f"[WARN] Multiple CH340 found: {candidates}, using {candidates[0]}")
        return candidates[0]
    return None


def make_decoder():
    """增量 UTF-8 解码器：按字节流实时解码，避免分段边界出现替换符"""
    return codecs.getincrementaldecoder("utf-8")("replace")


def write_console(text):
    """实时打印（不换行），立即刷出"""
    if text:
        sys.stdout.write(text)
        sys.stdout.flush()


def interactive_terminal(ser, log_path=None, echo=True):
    """交互终端：实时回显 RX + 键盘输入转发 TX，Ctrl+C 退出

    echo=True 时键盘输入同时本地回显（默认），远端设备自身回显时用
    --no-echo 避免双字符；回显仅在标准输出为终端时使用颜色区分。
    log_path 须为调用方已按仓库子树校验过的绝对路径。
    """
    decoder = make_decoder()
    logf = None
    if log_path:
        if is_inside_repo(log_path):
            logf = open(log_path, "wb")
        else:
            print(f"[WARN] log path escaped repo, disabled logging: {log_path}", file=sys.stderr)
    use_color = echo and sys.stdout.isatty()
    print(f"[TERM] Interactive terminal on {ser.port} @ {ser.baudrate}: "
          "RX -> console, keyboard -> TX. "
          + ("local echo on, " if echo else "local echo off, ")
          + "Ctrl+C to exit.")

    def tx_echo(ch):
        """转发键盘输入并（可选）本地回显"""
        ser.write(ch)
        if echo:
            if use_color:
                sys.stdout.write("\x1b[36m")  # 青色：本地输入
            sys.stdout.buffer.write(ch)
            sys.stdout.buffer.flush()
            if use_color:
                sys.stdout.write("\x1b[0m")
                sys.stdout.flush()

    if os.name == "nt":
        import msvcrt
        try:
            while True:
                if ser.in_waiting:
                    data = ser.read(ser.in_waiting)
                    if logf:
                        logf.write(data)
                    write_console(decoder.decode(data))
                if msvcrt.kbhit():
                    ch = msvcrt.getch()
                    if ch == b"\x03":  # Ctrl+C
                        break
                    tx_echo(ch)
                time.sleep(0.01)
        except KeyboardInterrupt:
            pass
    else:
        import select
        import termios
        import tty
        fd = sys.stdin.fileno()
        old = termios.tcgetattr(fd)
        tty.setcbreak(fd)
        try:
            while True:
                if ser.in_waiting:
                    data = ser.read(ser.in_waiting)
                    if logf:
                        logf.write(data)
                    write_console(decoder.decode(data))
                r, _, _ = select.select([sys.stdin], [], [], 0.01)
                if r:
                    ch = os.read(fd, 1)
                    if ch == b"\x03":  # Ctrl+C
                        break
                    tx_echo(ch)
        except KeyboardInterrupt:
            pass
        finally:
            termios.tcsetattr(fd, termios.TCSADRAIN, old)

    if logf:
        logf.close()
    print("\r[TERM] session ended.")


def main():
    parser = argparse.ArgumentParser(
        description="BD32 UART Program Downloader / Interactive Terminal")
    parser.add_argument("file", nargs="?", default=None,
                        help="uartbin file to send (download mode; not needed with --interactive)")
    parser.add_argument("--port", default=None,
                        help="COM port (default: auto-detect CH340)")
    parser.add_argument("--baud", type=int, default=115200,
                        help="Baud rate (default: 115200)")
    parser.add_argument("--chunk", type=int, default=256,
                        help="Chunk size in bytes (default: 256)")
    parser.add_argument("--delay", type=float, default=0.01,
                        help="Delay between chunks in seconds (default: 0.01)")
    parser.add_argument("--reset", action="store_true",
                        help="Reset FPGA before sending (requires fpga_reset.py)")
    parser.add_argument("--idle-timeout", type=float, default=None,
                        help="开启监听：连续 N 秒无数据即停止（默认 3s）")
    parser.add_argument("--timeout", type=float, default=None,
                        help="监听总时长上限（默认 30s）")
    parser.add_argument("--until", default=None,
                        help="可选精确结束标记：命中后截断到标记末尾并停止")
    parser.add_argument("--early-warn", type=float, default=6.0,
                        help="下载后监听阶段：超过 N 秒仍 0 字节则打印一次'疑似不匹配/挂死'诊断（不中断，仅提示；设 0 关闭）")
    parser.add_argument("--log", default=None,
                        help="监听/交互输出写入的日志文件路径（监听默认 logs/uart_send_<程序>_<时间戳>.log，须在仓库目录内）")
    parser.add_argument("--interactive", action="store_true",
                        help="交互终端模式：实时回显 + 键盘转发，Ctrl+C 退出（无需 file）")
    parser.add_argument("--no-echo", action="store_true",
                        help="交互终端关闭本地回显（远端设备自身回显时用，避免双字符）")
    args = parser.parse_args()

    # 日志路径校验：--log 必须落在仓库目录内（防路径穿越写到任意位置）；
    # 顺手补父目录创建（interactive 与监听模式共用：此前 interactive 用户 --log
    # 指向不存在父目录会 FileNotFoundError，见 09 安全审计缺口2）
    if args.log is not None:
        args.log = safe_log_path(args.log, repo_root())
        os.makedirs(os.path.dirname(args.log) or ".", exist_ok=True)

    # 自动检测串口
    if args.port is None:
        args.port = find_port()
        if args.port is None:
            print("[ERROR] No CH340 USB-UART detected. Use --port to specify manually.")
            sys.exit(1)
        print(f"[AUTO] Detected UART: {args.port}")

    # 交互终端模式：不下载文件，直接收发
    if args.interactive:
        print(f"[TERM] Opening {args.port} @ {args.baud}...")
        ser = serial.Serial(args.port, args.baud, timeout=1)
        time.sleep(0.5)
        ser.reset_input_buffer()
        interactive_terminal(ser, args.log, echo=not args.no_echo)
        ser.close()
        return

    if args.file is None:
        print("[ERROR] 下载模式需要 uartbin 文件；交互终端请加 --interactive")
        sys.exit(1)

    if not os.path.exists(args.file):
        # 固定搜索位置（test_data/soc/c）：取 basename 防止 <file> 参数中的路径成分
        # 使拼接目标逃逸出该目录
        alt = os.path.join(repo_root(), "test_data", "soc", "c",
                           os.path.basename(args.file))
        if os.path.exists(alt):
            print(f"[INFO] 在 test_data/soc/c 下找到: {alt}")
            args.file = alt
        else:
            print(f"[ERROR] File not found: {args.file}")
            sys.exit(1)

    # 可选：先复位
    if args.reset:
        print("[1/3] Resetting FPGA...")
        script_dir = os.path.dirname(os.path.abspath(__file__))
        subprocess.run([sys.executable, os.path.join(script_dir, "fpga_reset.py")], check=True)
        time.sleep(1.0)
        step = "2/3"
    else:
        step = "1/2"

    # 打开串口
    print(f"[{step}] Opening {args.port} @ {args.baud}...")
    ser = serial.Serial(args.port, args.baud, timeout=1)
    time.sleep(0.5)
    ser.reset_input_buffer()

    # 发送
    data = open(args.file, "rb").read()
    total = len(data)
    chunks = (total + args.chunk - 1) // args.chunk
    print(f"[{'3/3' if args.reset else '2/2'}] Sending {total} bytes ({chunks} chunks)...")

    for i in range(0, total, args.chunk):
        ser.write(data[i:i+args.chunk])
        time.sleep(args.delay)
        # 进度
        done = min(i + args.chunk, total)
        pct = done * 100 // total
        print(f"\r    {done}/{total} bytes ({pct}%)", end="", flush=True)

    ser.flush()
    print()

    # 发送后在同一串口会话内继续监听：Windows 串口独占，跨进程“先监听后发送”
    # 无法并发；先发送完再另开监听又会丢掉程序开头的输出，因此在本进程内读。
    if args.idle_timeout is not None or args.until is not None:
        idle = args.idle_timeout if args.idle_timeout is not None else 3.0
        timeout = args.timeout if args.timeout is not None else 30.0
        cond = "idle=%gs timeout=%gs" % (idle, timeout) + (" until='%s'" % args.until if args.until else "")
        print(f"[{step}] Listening ({cond})...")
        if args.log:
            log_path = args.log
        else:
            stem = os.path.splitext(os.path.basename(args.file))[0]
            # 纵深防御：只保留安全文件名字符，杜绝 basename 里混入 / .. 之类成分
            stem = "".join(ch for ch in stem if ch.isalnum() or ch in "._-") or "uartbin"
            ts = time.strftime("%Y%m%d_%H%M%S")
            log_dir = os.path.join(repo_root(), "logs")
            os.makedirs(log_dir, exist_ok=True)
            log_path = os.path.join(log_dir, "uart_send_%s_%s.log" % (stem, ts))
        print(f"  log → {os.path.abspath(log_path)}")
        buf = b""
        decoder = make_decoder()
        last_data = time.time()
        start = time.time()
        warned = False
        try:
            while time.time() - start < timeout:
                if ser.in_waiting > 0:
                    data = ser.read(ser.in_waiting)
                    buf += data
                    last_data = time.time()
                    # 实时打印（增量解码，避免分段边界乱码）
                    write_console(decoder.decode(data))
                    if args.until:
                        marker = args.until.encode()
                        idx = buf.find(marker)
                        if idx >= 0:
                            buf = buf[:idx + len(marker)]
                            break
                else:
                    # 早期存活检查：持续 0 字节超过 --early-warn 秒，提示一次
                    # （非致命，不中断监听——长静默计算类应用属正常；只防"静默拒收"）
                    if not warned and args.early_warn > 0 and len(buf) == 0 \
                            and (time.time() - start) >= args.early_warn:
                        warned = True
                        print(
                            f"\n[EARLY-WARN] {args.early_warn:g}s 内 0 字节。若最终仍 0 字节，"
                            "两种根因（先排挂死再判不匹配）：\n"
                            "  1) 板子挂死 → JTAG 重烧比特流（connect_hw_server→open_hw_target→"
                            "set_property PROGRAM.FILE <bit> [current_hw_device]→program_hw_devices），"
                            "重烧后本 uartbin 应立刻出数据；\n"
                            "  2) 固件↔比特流不匹配 → 用当前 build.py 重建该 .uartbin。\n"
                            "  判别法：先 JTAG 重烧再试一次——复活=挂死；仍 0 字节=不匹配(重建)。\n",
                            flush=True)
                    if time.time() - last_data >= idle:
                        break
                    time.sleep(0.05)
        except KeyboardInterrupt:
            pass
        # 冲刷增量解码器残余（对应 buf 末尾未完成的 UTF-8 字符）
        write_console(decoder.decode(b"", final=True))
        if buf:
            text = buf.decode("utf-8", errors="replace")
            if is_inside_repo(log_path):
                with open(log_path, "w", encoding="utf-8") as f:
                    f.write(text)
            else:
                print(f"[WARN] log path escaped repo, skipped write: {log_path}", file=sys.stderr)
        captured = len(buf)
        if captured == 0:
            # 0 字节 = 板子未产生任何输出：明确诊断（区分挂死/不匹配），不再笼统"sent successfully"
            print(f"\n[LISTEN] 0 字节（板子无输出）。诊断：JTAG 重烧比特流判别——"
                  "重烧后复活=板子挂死；仍 0 字节=固件↔比特流不匹配，用当前 build.py 重建 .uartbin。")
        else:
            print(f"\n[LISTEN DONE] captured {captured} bytes → {log_path}")

    ser.close()
    print(f"\n[DONE] {args.file} → {args.port} sent successfully.")

if __name__ == "__main__":
    main()
