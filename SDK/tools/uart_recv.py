"""
UART 接收工具 — 监听串口并打印输出到终端

用法：
    python tools/uart_recv.py                       # 自动检测串口，监听 30 秒
    python tools/uart_recv.py --timeout 60          # 监听 60 秒
    python tools/uart_recv.py --until "CoreMark"    # 收到包含指定字符串后停止
    python tools/uart_recv.py --port COM8 --baud 115200
"""
import serial
import serial.tools.list_ports
import time
import argparse
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
    parser = argparse.ArgumentParser(description="BD32 UART Receiver")
    parser.add_argument("--port", default=None, help="COM port (default: auto-detect CH340)")
    parser.add_argument("--baud", type=int, default=115200, help="Baud rate (default: 115200)")
    parser.add_argument("--timeout", type=float, default=30, help="Listen duration in seconds (default: 30)")
    parser.add_argument("--until", default=None, help="Stop when output contains this string")
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

    print(f"[LISTEN] {args.port} @ {args.baud}, timeout={args.timeout}s"
          + (f", until='{args.until}'" if args.until else ""))
    print("-" * 50)

    output = b""
    start = time.time()
    try:
        while time.time() - start < args.timeout:
            if ser.in_waiting > 0:
                chunk = ser.read(ser.in_waiting)
                output += chunk
                text = chunk.decode("utf-8", errors="replace")
                print(text, end="", flush=True)
                # 检查结束条件
                if args.until and args.until.encode() in output:
                    time.sleep(0.5)
                    if ser.in_waiting > 0:
                        tail = ser.read(ser.in_waiting)
                        output += tail
                        print(tail.decode("utf-8", errors="replace"), end="", flush=True)
                    break
            else:
                time.sleep(0.05)
    except KeyboardInterrupt:
        print("\n[INTERRUPTED]")

    ser.close()
    print(f"\n{'-' * 50}")
    print(f"[DONE] Received {len(output)} bytes in {time.time()-start:.1f}s")

if __name__ == "__main__":
    main()
