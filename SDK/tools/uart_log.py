"""
UART 日志记录工具 — 监听串口并将输出写入文件

用法：
    python tools/uart_log.py output.log                   # 自动检测串口，监听 30 秒
    python tools/uart_log.py result.txt --timeout 60      # 监听 60 秒
    python tools/uart_log.py log.txt --until "DONE"       # 收到 "DONE" 后停止
    python tools/uart_log.py log.txt --append             # 追加模式（默认覆盖）
    python tools/uart_log.py log.txt --quiet              # 不打印到终端，只写文件
"""
import serial
import serial.tools.list_ports
import time
import argparse
import os
import sys

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
    parser = argparse.ArgumentParser(description="BD32 UART Logger")
    parser.add_argument("output", help="Output log file path")
    parser.add_argument("--port", default=None, help="COM port (default: auto-detect CH340)")
    parser.add_argument("--baud", type=int, default=115200, help="Baud rate (default: 115200)")
    parser.add_argument("--timeout", type=float, default=30, help="Listen duration in seconds (default: 30)")
    parser.add_argument("--until", default=None, help="Stop when output contains this string")
    parser.add_argument("--append", action="store_true", help="Append to file instead of overwrite")
    parser.add_argument("--quiet", action="store_true", help="Don't print to terminal")
    args = parser.parse_args()

    # 自动检测串口
    if args.port is None:
        args.port = find_port()
        if args.port is None:
            print("[ERROR] No CH340 USB-UART detected. Use --port to specify manually.")
            sys.exit(1)

    ser = serial.Serial(args.port, args.baud, timeout=1)
    time.sleep(0.3)
    ser.reset_input_buffer()

    mode = "a" if args.append else "w"
    print(f"[LOG] {args.port} @ {args.baud} → {os.path.abspath(args.output)}")
    print(f"      timeout={args.timeout}s, mode={'append' if args.append else 'overwrite'}"
          + (f", until='{args.until}'" if args.until else ""))

    total = 0
    start = time.time()
    try:
        with open(args.output, mode, encoding="utf-8") as f:
            while time.time() - start < args.timeout:
                if ser.in_waiting > 0:
                    chunk = ser.read(ser.in_waiting)
                    text = chunk.decode("utf-8", errors="replace")
                    f.write(text)
                    f.flush()
                    total += len(chunk)
                    if not args.quiet:
                        print(text, end="", flush=True)
                    # 检查结束条件
                    if args.until and args.until.encode() in chunk:
                        time.sleep(0.5)
                        if ser.in_waiting > 0:
                            tail = ser.read(ser.in_waiting)
                            f.write(tail.decode("utf-8", errors="replace"))
                            f.flush()
                            total += len(tail)
                            if not args.quiet:
                                print(tail.decode("utf-8", errors="replace"), end="", flush=True)
                        break
                else:
                    time.sleep(0.05)
    except KeyboardInterrupt:
        print("\n[INTERRUPTED]")

    ser.close()
    elapsed = time.time() - start
    print(f"\n[DONE] {total} bytes in {elapsed:.1f}s → {os.path.abspath(args.output)}")

if __name__ == "__main__":
    main()
