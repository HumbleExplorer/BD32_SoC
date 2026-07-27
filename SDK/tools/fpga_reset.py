"""
BD32 FPGA 复位控制工具
通过 Sipeed RV-Debugger (FTDI FT2232H) 的 ADBUS5 引脚控制 FPGA 复位。

用法：
    python tools/fpga_reset.py          # 复位一次（拉高0.5秒后释放）
    python tools/fpga_reset.py --hold 3 # 保持复位3秒后释放
    python tools/fpga_reset.py --assert  # 仅拉高（保持复位，不释放）
    python tools/fpga_reset.py --release # 仅释放复位
"""
import ftd2xx
import time
import sys
import argparse

RST_BIT = 0x20  # ADBUS5 = bit5

def find_debugger():
    num = ftd2xx.createDeviceInfoList()
    for i in range(num):
        info = ftd2xx.getDeviceInfoDetail(i)
        if b'RS232 A' in info['description']:
            return i
    return None

def open_channel(idx):
    dev = ftd2xx.open(idx)
    dev.resetDevice()
    time.sleep(0.05)
    dev.purge(0x03)
    dev.setBitMode(RST_BIT, 0x01)  # bit-bang, only RST bit as output
    time.sleep(0.05)
    return dev

def main():
    parser = argparse.ArgumentParser(description="BD32 FPGA Reset via Sipeed RV-Debugger")
    parser.add_argument("--hold", type=float, default=0.5, help="Reset hold time in seconds (default: 0.5)")
    parser.add_argument("--assert", action="store_true", help="Assert reset and keep (don't release)")
    parser.add_argument("--release", action="store_true", help="Release reset only")
    args = parser.parse_args()

    idx = find_debugger()
    if idx is None:
        print("[ERROR] Sipeed RV-Debugger not found. Check USB connection.")
        sys.exit(1)

    dev = open_channel(idx)

    if args.release:
        dev.write(b'\x00')
        print("[OK] Reset released.")
    elif getattr(args, 'assert'):
        dev.write(bytes([RST_BIT]))
        print("[OK] Reset asserted (holding). Run with --release to free.")
    else:
        dev.write(bytes([RST_BIT]))
        print(f"[..] Reset asserted, holding {args.hold}s...")
        time.sleep(args.hold)
        dev.write(b'\x00')
        print("[OK] Reset released. Board restarting.")

    if not getattr(args, 'assert'):
        dev.setBitMode(0x00, 0x00)
        dev.close()

if __name__ == "__main__":
    main()
