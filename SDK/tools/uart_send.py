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
    """
    decoder = make_decoder()
    logf = None
    if log_path:
        os.makedirs(os.path.dirname(os.path.abspath(log_path)), exist_ok=True)
        logf = open(log_path, "wb")
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
    parser.add_argument("--log", default=None,
                        help="监听/交互输出写入的日志文件路径（监听默认 logs/uart_send_<程序>_<时间戳>.log）")
    parser.add_argument("--interactive", action="store_true",
                        help="交互终端模式：实时回显 + 键盘转发，Ctrl+C 退出（无需 file）")
    parser.add_argument("--no-echo", action="store_true",
                        help="交互终端关闭本地回显（远端设备自身回显时用，避免双字符）")
    args = parser.parse_args()

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
        alt = os.path.normpath(os.path.join(
            os.path.dirname(os.path.abspath(__file__)),
            "..", "..", "test_data", "soc", "c", args.file))
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
            ts = time.strftime("%Y%m%d_%H%M%S")
            log_dir = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), "logs")
            os.makedirs(log_dir, exist_ok=True)
            log_path = os.path.join(log_dir, "uart_send_%s_%s.log" % (stem, ts))
        print(f"  log → {os.path.abspath(log_path)}")
        buf = b""
        decoder = make_decoder()
        last_data = time.time()
        start = time.time()
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
                    if time.time() - last_data >= idle:
                        break
                    time.sleep(0.05)
        except KeyboardInterrupt:
            pass
        # 冲刷增量解码器残余（对应 buf 末尾未完成的 UTF-8 字符）
        write_console(decoder.decode(b"", final=True))
        if buf:
            text = buf.decode("utf-8", errors="replace")
            with open(log_path, "w", encoding="utf-8") as f:
                f.write(text)
        print(f"\n[LISTEN DONE] captured {len(buf)} bytes → {log_path}")

    ser.close()
    print(f"\n[DONE] {args.file} → {args.port} sent successfully.")

if __name__ == "__main__":
    main()
