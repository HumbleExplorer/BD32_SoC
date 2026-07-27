"""
UART 命令/文本发送工具 — 通过串口发送任意文本或十六进制数据

用法：
    python tools/uart_cmd.py "hello"                    # 发送文本（自动加换行，自动检测串口）
    python tools/uart_cmd.py "hello" --no-newline       # 不加换行
    python tools/uart_cmd.py --hex "AA BB CC 01"       # 发送原始字节
    python tools/uart_cmd.py --file cmd.txt             # 发送文件内容
    python tools/uart_cmd.py "test" --port COM8 --baud 115200
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
    parser = argparse.ArgumentParser(description="BD32 UART Command Sender")
    parser.add_argument("text", nargs="?", default=None, help="Text string to send")
    parser.add_argument("--hex", default=None, help="Hex bytes to send (e.g. 'AA BB CC 01')")
    parser.add_argument("--file", default=None, help="Send content of a text file")
    parser.add_argument("--port", default=None, help="COM port (default: auto-detect CH340)")
    parser.add_argument("--baud", type=int, default=115200, help="Baud rate (default: 115200)")
    parser.add_argument("--no-newline", action="store_true", help="Don't append newline to text")
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
    ser.close()
    print(f"[OK] Sent {desc} → {args.port} ({len(data)} bytes)")

if __name__ == "__main__":
    main()
