"""板上 uart_irq 验证：编程新比特流后，下载固件 + 发 3 行 + 收回显判定。

用法: python SDK/tools/board_uart_irq_test.py [--port COM8]
协议：裸 open 复位进 BootROM 下载模式 → 分块发 uartbin → 同会话等横幅/发3行/收回显。
"""
import sys, os, time, argparse

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import serial
from uart_send import find_port

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

REPO = os.path.realpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
BIN = os.path.join(REPO, "test_data", "soc", "c", "uart_irq_os.uartbin")

parser = argparse.ArgumentParser()
parser.add_argument("--port", default=None)
args = parser.parse_args()

port = args.port or find_port()
print(f"[PORT] {port}")
ser = serial.Serial(port, 115200, timeout=0.2)
time.sleep(0.5)
ser.reset_input_buffer()          # 裸 open 已复位板子，BootROM 进入下载模式

data = open(BIN, "rb").read()
print(f"[DL] {len(data)} bytes")
for i in range(0, len(data), 256):
    ser.write(data[i:i+256])
    time.sleep(0.01)
ser.flush()

def pump(seconds):
    out = b""
    end = time.time() + seconds
    while time.time() < end:
        if ser.in_waiting:
            out += ser.read(ser.in_waiting)
        else:
            time.sleep(0.02)
    return out

banner = pump(2.0)
print("[BANNER]", repr(banner.decode("utf-8", "replace")))

log = banner
for line in ("hello", "uart", "irq"):
    ser.write((line + "\r\n").encode())
    out = pump(1.0)
    log += out
    print(f"[AFTER {line}]", repr(out.decode("utf-8", "replace")))

tail = pump(2.0)
log += tail
print("[TAIL]", repr(tail.decode("utf-8", "replace")))

text = log.decode("utf-8", "replace")
ok = ("rx1:hello" in text) and ("rx2:uart" in text) and ("rx3:irq" in text) and ("PASS!" in text)
print("\n=== BOARD TEST %s ===" % ("PASSED" if ok else "FAILED"))
ser.close()
sys.exit(0 if ok else 1)
