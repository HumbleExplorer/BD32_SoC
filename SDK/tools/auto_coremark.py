"""
BD32 CoreMark 自动化测试脚本
流程：复位 → UART下载程序 → 等待输出 → 解析结果

用法：
    python tools/auto_coremark.py                          # 跑全部9个配置
    python tools/auto_coremark.py --config coremark_o2     # 只跑一个
    python tools/auto_coremark.py --port COM8 --baud 115200
"""
import ftd2xx
import serial
import serial.tools.list_ports
import time
import struct
import argparse
import os
import sys
import re

# ============================================================
# 配置
# ============================================================
RST_BIT = 0x20          # ADBUS5
RESET_HOLD = 0.5        # 复位保持时间(秒)
BOOT_DELAY = 1.0        # 复位释放后等BootROM启动(秒)
SEND_CHUNK = 256        # 串口发送分块大小
SEND_DELAY = 0.01       # 每块间隔(秒)
RESULT_TIMEOUT = 300    # 等待结果超时(秒), CoreMark 500轮约需3-4分钟

# 9个测试配置: (名称, uartbin文件名)
CONFIGS = [
    ("GCC Os",   "coremark_os.uartbin"),
    ("GCC O1",   "coremark_o1.uartbin"),
    ("GCC O2",   "coremark_o2.uartbin"),
    ("GCC O3",   "coremark_o3.uartbin"),
    ("LLVM Os",  "coremark_clang_os.uartbin"),
    ("LLVM Oz",  "coremark_clang_oz.uartbin"),
    ("LLVM O1",  "coremark_clang_o1.uartbin"),
    ("LLVM O2",  "coremark_clang_o2.uartbin"),
    ("LLVM O3",  "coremark_clang_o3.uartbin"),
]

# ============================================================
# 串口自动检测
# ============================================================
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

# ============================================================
# 复位控制
# ============================================================
def find_debugger():
    num = ftd2xx.createDeviceInfoList()
    for i in range(num):
        info = ftd2xx.getDeviceInfoDetail(i)
        if b'RS232 A' in info['description']:
            return i
    return None

def reset_fpga():
    idx = find_debugger()
    if idx is None:
        print("[ERROR] Sipeed RV-Debugger not found!")
        return False
    dev = ftd2xx.open(idx)
    dev.resetDevice()
    time.sleep(0.05)
    dev.purge(0x03)
    dev.setBitMode(RST_BIT, 0x01)
    time.sleep(0.05)
    dev.write(bytes([RST_BIT]))   # assert reset
    time.sleep(RESET_HOLD)
    dev.write(b'\x00')            # release reset
    time.sleep(0.05)
    dev.setBitMode(0x00, 0x00)
    dev.close()
    return True

# ============================================================
# UART 下载
# ============================================================
def send_program(ser, filepath):
    data = open(filepath, 'rb').read()
    print(f"    Sending {len(data)} bytes ({len(data)//SEND_CHUNK+1} chunks)...")
    for i in range(0, len(data), SEND_CHUNK):
        chunk = data[i:i+SEND_CHUNK]
        ser.write(chunk)
        time.sleep(SEND_DELAY)
    ser.flush()
    print(f"    Send complete.")

# ============================================================
# 等待并解析结果
# ============================================================
def wait_for_result(ser, timeout=RESULT_TIMEOUT):
    """等待 CoreMark 输出完成，返回全部输出文本"""
    print(f"    Waiting for CoreMark output (timeout={timeout}s)...")
    output = b""
    start = time.time()
    done = False

    while time.time() - start < timeout:
        if ser.in_waiting > 0:
            chunk = ser.read(ser.in_waiting)
            output += chunk
            text = output.decode('utf-8', errors='replace')
            # 检测完成标志
            if "Correct operation validated" in text or "CoreMark/MHz" in text:
                # 多等2秒确保输出完整
                time.sleep(2)
                if ser.in_waiting > 0:
                    output += ser.read(ser.in_waiting)
                done = True
                break
        else:
            time.sleep(0.1)

    text = output.decode('utf-8', errors='replace')
    if not done:
        print(f"    [WARN] Timeout! Got {len(output)} bytes so far.")
    return text, done

def parse_coremark(text):
    """从输出文本中解析 CoreMark 结果"""
    result = {}

    m = re.search(r'CoreMark/MHz\s*[:\s]+([\d.]+)', text)
    if m: result['coremark_mhz'] = float(m.group(1))

    m = re.search(r'Iterations/Sec\s*[:\s]+([\d.]+)', text)
    if m: result['iter_per_sec'] = float(m.group(1))

    m = re.search(r'Total ticks\s*[:\s]+(\d+)', text)
    if m: result['total_ticks'] = int(m.group(1))

    m = re.search(r'Predict rate\s*:\s*([0-9.]+)\s*%', text)
    if m: result['branch_hit'] = float(m.group(1)) / 100.0

    return result

# ============================================================
# 主流程
# ============================================================
def run_single(ser, name, uartbin_path):
    print(f"\n{'='*60}")
    print(f"  Config: {name}")
    print(f"  File:   {uartbin_path}")
    print(f"{'='*60}")

    # 1. 复位
    print("  [1/4] Resetting FPGA...")
    if not reset_fpga():
        return None
    time.sleep(BOOT_DELAY)

    # 2. 下载
    print("  [2/4] Downloading program...")
    ser.reset_input_buffer()
    send_program(ser, uartbin_path)

    # 3. 等待结果
    print("  [3/4] Running CoreMark...")
    text, ok = wait_for_result(ser)

    # 4. 解析
    print("  [4/4] Parsing results...")
    if ok:
        result = parse_coremark(text)
        print(f"    CoreMark/MHz:   {result.get('coremark_mhz', 'N/A')}")
        print(f"    Iterations/Sec: {result.get('iter_per_sec', 'N/A')}")
        print(f"    Total ticks:    {result.get('total_ticks', 'N/A')}")
        print(f"    Branch hit:     {result.get('branch_hit', 'N/A')}")
        return result
    else:
        print(f"    [FAILED] No valid result. Last 200 chars:")
        print(f"    {text[-200:]}")
        return None

def main():
    parser = argparse.ArgumentParser(description="BD32 CoreMark Auto Test")
    parser.add_argument("--port", default=None, help="UART COM port (default: auto-detect CH340)")
    parser.add_argument("--baud", type=int, default=115200, help="Baud rate (default: 115200)")
    parser.add_argument("--config", default=None, help="Run single config by name prefix (e.g. coremark_o2)")
    parser.add_argument("--data-dir", default=None, help="Path to uartbin files")
    args = parser.parse_args()

    # 自动检测串口
    if args.port is None:
        args.port = find_port()
        if args.port is None:
            print("[ERROR] No CH340 USB-UART detected. Use --port to specify manually.")
            sys.exit(1)
        print(f"[AUTO] Detected UART: {args.port}")

    # 确定数据目录
    if args.data_dir:
        data_dir = args.data_dir
    else:
        script_dir = os.path.dirname(os.path.abspath(__file__))
        data_dir = os.path.join(script_dir, "..", "..", "test_data", "soc", "c")
        data_dir = os.path.normpath(data_dir)

    print(f"UART: {args.port} @ {args.baud}")
    print(f"Data: {data_dir}")

    # 筛选配置
    configs = CONFIGS
    if args.config:
        configs = [(n, f) for n, f in CONFIGS if args.config in f]
        if not configs:
            print(f"[ERROR] No config matching '{args.config}'")
            sys.exit(1)

    # 打开串口
    ser = serial.Serial(args.port, args.baud, timeout=1)
    time.sleep(0.5)

    results = {}
    for name, filename in configs:
        filepath = os.path.join(data_dir, filename)
        if not os.path.exists(filepath):
            print(f"\n[SKIP] {name}: file not found ({filepath})")
            continue
        result = run_single(ser, name, filepath)
        results[name] = result

    ser.close()

    # 汇总
    print(f"\n\n{'='*60}")
    print("  SUMMARY")
    print(f"{'='*60}")
    print(f"{'Config':<12} {'CoreMark/MHz':<14} {'Iter/Sec':<12} {'Ticks':<12} {'Branch%':<10}")
    print("-" * 60)
    for name, _ in configs:
        r = results.get(name)
        if r:
            print(f"{name:<12} {r.get('coremark_mhz',''):<14} {r.get('iter_per_sec',''):<12} "
                  f"{r.get('total_ticks',''):<12} {r.get('branch_hit',''):<10}")
        else:
            print(f"{name:<12} {'FAILED':<14}")

if __name__ == "__main__":
    main()
