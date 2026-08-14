"""
BD32 FPGA 复位控制工具
默认通过 OpenOCD 驱动 Sipeed RV-Debugger (FT2232H) 的 ADBUS5 引脚复位 FPGA
（WinUSB 模式即可，无需 ftd2xx / 无需切换驱动；方案参考 E203 SDK openocd_evalsoc.cfg）。

用法：
    python tools/fpga_reset.py                  # 复位一次（拉高 0.5 秒后释放）
    python tools/fpga_reset.py --hold 3         # 保持复位 3 秒后释放
    python tools/fpga_reset.py --assert          # 仅拉高（保持复位）
    python tools/fpga_reset.py --release         # 仅释放
    python tools/fpga_reset.py --method ftd2xx   # 强制走 ftd2xx（OpenOCD 不可用时回退）
环境变量：OPENOCD（openocd 可执行文件路径，默认 third_party/xpack-openocd）
"""
import subprocess
import sys
import os
import argparse
import time

RST_BIT = 0x20          # ADBUS5，高有效复位

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.abspath(os.path.join(SCRIPT_DIR, "..", ".."))
OPENOCD = os.environ.get("OPENOCD", os.path.join(
    REPO_ROOT, "third_party", "xpack-openocd-0.12.0-7", "bin", "openocd.exe"))
OCD_CFG = os.path.join(REPO_ROOT, "SDK", "tools", "bd32_reset.cfg")


def reset_openocd(hold_ms, action):
    """通过 OpenOCD 驱动 ADBUS5 复位。action: pulse / assert / release"""
    cmd = {"pulse": "fpga_reset %d" % hold_ms,
           "assert": "fpga_reset_assert",
           "release": "fpga_reset_release"}[action]
    args = [OPENOCD, "-f", OCD_CFG, "-c", "init", "-c", cmd, "-c", "shutdown"]
    r = subprocess.run(args, capture_output=True, text=True, errors="replace")
    if r.returncode != 0:
        print("[ERROR] OpenOCD reset failed: %s" % ((r.stderr or r.stdout)[-400:]))
        return False
    return True


def reset_ftd2xx(hold, assert_only, release_only):
    """旧方案：ftd2xx (D2XX) 位带模式驱动 ADBUS5（需 FTDI VCP 驱动，与 OpenOCD/WinUSB 互斥）"""
    try:
        import ftd2xx
    except ImportError:
        print("[ERROR] ftd2xx 未安装（pip install ftd2xx），且 OpenOCD 复位失败")
        return False

    def find_debugger():
        num = ftd2xx.createDeviceInfoList()
        for i in range(num):
            info = ftd2xx.getDeviceInfoDetail(i)
            if b'RS232 A' in info['description']:
                return i
        return None

    idx = find_debugger()
    if idx is None:
        print("[ERROR] Sipeed RV-Debugger (ftd2xx) not found.")
        return False
    dev = ftd2xx.open(idx)
    dev.resetDevice()
    time.sleep(0.05)
    dev.purge(0x03)
    dev.setBitMode(RST_BIT, 0x01)
    time.sleep(0.05)
    if release_only:
        dev.write(b'\x00')
    else:
        dev.write(bytes([RST_BIT]))
        if not assert_only:
            time.sleep(hold)
            dev.write(b'\x00')
    if not assert_only:
        dev.setBitMode(0x00, 0x00)
    dev.close()
    return True


def main():
    parser = argparse.ArgumentParser(description="BD32 FPGA Reset (OpenOCD/ADBUS5)")
    parser.add_argument("--hold", type=float, default=0.5, help="Reset hold time in seconds")
    parser.add_argument("--assert", action="store_true", help="Assert reset and keep")
    parser.add_argument("--release", action="store_true", help="Release reset only")
    parser.add_argument("--method", choices=["openocd", "ftd2xx"], default=None,
                        help="Force reset method (default: openocd, fallback ftd2xx)")
    args = parser.parse_args()

    assert_flag = getattr(args, "assert")
    if args.release or assert_flag:
        # 优先 OpenOCD（WinUSB 模式即可）；若 OpenOCD 失败再回退 ftd2xx
        action = "release" if args.release else "assert"
        ok = reset_openocd(int(args.hold * 1000), action)
        if not ok and args.method != "openocd":
            print("[WARN] OpenOCD assert/release 失败，回退 ftd2xx（需 FTDI VCP 驱动）…")
            ok = reset_ftd2xx(args.hold, assert_flag, args.release)
    elif args.method == "ftd2xx":
        ok = reset_ftd2xx(args.hold, False, False)
    else:
        ok = reset_openocd(int(args.hold * 1000), "pulse")
        if not ok and args.method is None:
            print("[WARN] 回退到 ftd2xx 方式…")
            ok = reset_ftd2xx(args.hold, False, False)

    if ok:
        print("[OK] FPGA reset done.")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
