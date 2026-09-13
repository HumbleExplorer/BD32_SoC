#!/usr/bin/env python3
# BD32 板上长稳 soak 串口监听：持续记录 UART 输出，检测 SERR
# 用法：python soak_uart_listener.py [小时数，默认 12]
# 判据：日志出现 "[SERR]" 即 bug 复发（同时写 logs/soak_SERR_FOUND.marker）
import serial, sys, time, os

HOURS = float(sys.argv[1]) if len(sys.argv) > 1 else 12.0
PORT, BAUD = 'COM8', 115200
LOG = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'logs', 'soak_uart.log')
MARK = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'logs', 'soak_SERR_FOUND.marker')

deadline = time.time() + HOURS * 3600
# DTR 安全打开：先配置再 open，避免 open() 的 DTR 脉冲把板子复位进
# BootROM 下载等待（板载 CH340 DTR/RTS 接复位/下载电路；裸 open 曾致
# 全程静默——2026-09-14 soak 教训）
ser = serial.Serial()
ser.port, ser.baudrate, ser.timeout = PORT, BAUD, 1
ser.dtr, ser.rts = False, False
ser.open()
buf = []
with open(LOG, 'a', encoding='utf-8', errors='replace') as f:
    f.write(f"\n===== soak start {time.strftime('%Y-%m-%d %H:%M:%S')} ({HOURS}h) =====\n")
    f.flush()
    while time.time() < deadline:
        data = ser.read(4096)
        if not data:
            continue
        text = data.decode('utf-8', errors='replace')
        buf.append(text)
        if b'SERR' in data:
            with open(MARK, 'a') as m:
                m.write(f"{time.strftime('%Y-%m-%d %H:%M:%S')} SERR detected\n")
        if time.strftime('%M:%S').endswith('00:00'):
            buf.append(f"\n[--- {time.strftime('%Y-%m-%d %H:%M')} ---]\n")
        if sum(len(x) for x in buf) > 65536:
            f.write(''.join(buf)); f.flush(); buf.clear()
    f.write(''.join(buf))
    f.write(f"\n===== soak end {time.strftime('%Y-%m-%d %H:%M:%S')} =====\n")
ser.close()
