"""
BD32 FPGA 复位引脚测试脚本
用法：python reset_test.py
逐个测试 FTDI Channel A 的 bit0~bit7，按 Enter 进入下一个。
"""
import ftd2xx
import time
import sys

def main():
    # 枚举设备
    num = ftd2xx.createDeviceInfoList()
    target = None
    for i in range(num):
        info = ftd2xx.getDeviceInfoDetail(i)
        if b'RS232 A' in info['description']:
            target = i
            break

    if target is None:
        print("[ERROR] 未找到 Sipeed RV-Debugger (Dual RS232 A)")
        print("        请确认调试器已插入 USB")
        sys.exit(1)

    print(f"[OK] 找到调试器: index={target}")
    print("=" * 50)
    print("测试流程：逐个拉高 Channel A 的 bit0~bit7")
    print("每步按 Enter 开始拉高（保持5秒），观察灯是否灭")
    print("按 q 退出")
    print("=" * 50)

    dev = ftd2xx.open(target)
    dev.resetDevice()
    time.sleep(0.1)
    dev.purge(0x03)
    dev.setBitMode(0xFF, 0x01)  # bit-bang, all output
    time.sleep(0.1)

    for bit in range(8):
        val = 1 << bit
        print(f"\n--- 准备测试 bit{bit} (0x{val:02x}) ---")
        print(f"    对应引脚: ADBUS{bit}", end="")
        if bit == 0: print(" (TCK)")
        elif bit == 1: print(" (TDI)")
        elif bit == 2: print(" (TDO)")
        elif bit == 3: print(" (TMS)")
        else: print(f" (GPIO{bit-4})")

        cmd = input("    按 Enter 拉高5秒 / 输入 q 退出: ").strip()
        if cmd.lower() == 'q':
            break

        print(f"    >>> bit{bit} = HIGH (5秒) <<<")
        dev.write(bytes([val]))
        time.sleep(5)
        dev.write(b'\x00')
        print(f"    >>> bit{bit} = LOW (已释放) <<<")

        result = input("    灯灭了吗？(y/n/q): ").strip().lower()
        if result == 'y':
            print(f"\n{'='*50}")
            print(f"  [结果] RST 引脚 = ADBUS{bit} (bit{bit}, 0x{val:02x})")
            print(f"{'='*50}")
            dev.setBitMode(0x00, 0x00)
            dev.close()
            return
        elif result == 'q':
            break

    dev.setBitMode(0x00, 0x00)
    dev.close()
    print("\n[完成] 未找到有效复位引脚，请检查接线。")

if __name__ == "__main__":
    main()
