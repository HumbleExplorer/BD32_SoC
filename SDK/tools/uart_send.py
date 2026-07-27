"""
UART 程序烧录工具 — 将 .uartbin 文件通过串口下载到 FPGA

用法：
    python tools/uart_send.py <file.uartbin>              # 自动检测串口
    python tools/uart_send.py coremark_o2.uartbin --port COM8 --baud 115200
    python tools/uart_send.py coremark_o2.uartbin --reset   # 先复位再下载
"""
import serial
import serial.tools.list_ports
import time
import argparse
import os
import sys
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

def main():
    parser = argparse.ArgumentParser(description="BD32 UART Program Downloader")
    parser.add_argument("file", help="uartbin file to send")
    parser.add_argument("--port", default=None, help="COM port (default: auto-detect CH340)")
    parser.add_argument("--baud", type=int, default=115200, help="Baud rate (default: 115200)")
    parser.add_argument("--chunk", type=int, default=256, help="Chunk size in bytes (default: 256)")
    parser.add_argument("--delay", type=float, default=0.01, help="Delay between chunks in seconds (default: 0.01)")
    parser.add_argument("--reset", action="store_true", help="Reset FPGA before sending (requires fpga_reset.py)")
    args = parser.parse_args()

    # 自动检测串口
    if args.port is None:
        args.port = find_port()
        if args.port is None:
            print("[ERROR] No CH340 USB-UART detected. Use --port to specify manually.")
            sys.exit(1)
        print(f"[AUTO] Detected UART: {args.port}")

    if not os.path.exists(args.file):
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
    ser.close()
    print(f"\n[DONE] {args.file} → {args.port} sent successfully.")

if __name__ == "__main__":
    main()
