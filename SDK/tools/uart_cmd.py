"""
UART 命令/文本发送工具 — 通过串口发送任意文本或十六进制数据

用法：
    python tools/uart_cmd.py "hello"                    # 发送文本（自动加换行，自动检测串口）
    python tools/uart_cmd.py "hello" --no-newline       # 不加换行
    python tools/uart_cmd.py --hex "AA BB CC 01"       # 发送原始字节
    python tools/uart_cmd.py --file cmd.txt             # 发送文件内容
    python tools/uart_cmd.py "test" --port COM8 --baud 115200
    python tools/uart_cmd.py "hi" --idle-timeout 3      # 发送后监听，输出空闲 3s 停止
    python tools/uart_cmd.py "hi" --until "Done!"       # 发送后监听，精确停在标记末尾
"""
import serial
import serial.tools.list_ports
import time
import argparse
import os
import sys

# Windows 控制台（GBK）无法打印原始字节解码出的替换字符时避免崩溃
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

def find_port():
    """自动检测 CH340 USB-UART 串口"""
    candidates = []
    for p in serial.tools.list_ports.comports():
        desc = (p.description or "").upper()
        vid_pid = f"{p.vid:04X}:{p.pid:04X}" if p.vid else ""
        if "CH340" in desc or vid_pid == "1A86:7523":
            candidates.append(p.device)
    if len(candidates) == 1:
        return candidates[0]
    elif len(candidates) > 1:
        print(f"[WARN] Multiple CH340 found: {candidates}, using {candidates[0]}")
        return candidates[0]
    return None

def main():
    parser = argparse.ArgumentParser(description="BD32 UART Command Sender")
    parser.add_argument("text", nargs="?", default=None, help="Text string to send")
    parser.add_argument("--hex", default=None, help="Hex bytes to send (e.g. 'AA BB CC 01')")
    parser.add_argument("--file", default=None, help="Send content of a text file")
    parser.add_argument("--port", default=None, help="COM port (default: auto-detect CH340)")
    parser.add_argument("--baud", type=int, default=115200, help="Baud rate (default: 115200)")
    parser.add_argument("--no-newline", action="store_true", help="Don't append newline to text")
    parser.add_argument("--idle-timeout", type=float, default=None, help="开启监听：连续 N 秒无数据即停止（默认 3s）")
    parser.add_argument("--timeout", type=float, default=None, help="监听总时长上限（默认 30s）")
    parser.add_argument("--until", default=None, help="可选精确结束标记：命中后截断到标记末尾并停止")
    parser.add_argument("--log", default=None, help="监听输出写入的日志文件路径（默认 logs/uart_cmd_<时间戳>.log）")
    args = parser.parse_args()

    # 自动检测串口
    if args.port is None:
        args.port = find_port()
        if args.port is None:
            print("[ERROR] No CH340 USB-UART detected. Use --port to specify manually.")
            sys.exit(1)

    # 确定要发送的数据
    if args.hex:
        hex_str = args.hex.replace(" ", "").replace("0x", "").replace(",", "")
        try:
            data = bytes.fromhex(hex_str)
        except ValueError:
            print(f"[ERROR] Invalid hex string: {args.hex}")
            sys.exit(1)
        desc = f"hex {len(data)} bytes"
    elif args.file:
        with open(args.file, "rb") as f:
            data = f.read()
        desc = f"file {args.file} ({len(data)} bytes)"
    elif args.text:
        text = args.text if args.no_newline else args.text + "\n"
        data = text.encode("utf-8")
        desc = f'"{args.text}"'
    else:
        parser.print_help()
        sys.exit(1)

    # 发送
    ser = serial.Serial(args.port, args.baud, timeout=1)
    time.sleep(0.3)
    ser.write(data)
    ser.flush()

    if args.idle_timeout is not None or args.until is not None:
        idle = args.idle_timeout if args.idle_timeout is not None else 3.0
        timeout = args.timeout if args.timeout is not None else 30.0
        cond = "idle=%gs timeout=%gs" % (idle, timeout) + (" until='%s'" % args.until if args.until else "")
        print(f"[LISTEN] {cond}...")
        if args.log:
            log_path = args.log
        else:
            ts = time.strftime("%Y%m%d_%H%M%S")
            log_dir = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), "logs")
            os.makedirs(log_dir, exist_ok=True)
            log_path = os.path.join(log_dir, "uart_cmd_%s.log" % ts)
        print(f"  log → {os.path.abspath(log_path)}")
        buf = b""
        last_data = time.time()
        start = time.time()
        try:
            while time.time() - start < timeout:
                if ser.in_waiting > 0:
                    buf += ser.read(ser.in_waiting)
                    last_data = time.time()
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
        if buf:
            text = buf.decode("utf-8", errors="replace")
            with open(log_path, "w", encoding="utf-8") as f:
                f.write(text)
            print(text, end="", flush=True)
        print(f"\n[LISTEN DONE] captured {len(buf)} bytes → {log_path}")

    ser.close()
    print(f"[OK] Sent {desc} → {args.port} ({len(data)} bytes)")

if __name__ == "__main__":
    main()
