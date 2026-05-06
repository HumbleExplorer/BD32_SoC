import sys

with open(sys.argv[1], 'rb') as f:
    data = f.read()

if len(data) % 4 != 0:
    data += b'\x00' * (4 - len(data) % 4)

out_path = sys.argv[2] if len(sys.argv) > 2 else sys.argv[1].replace('.bin', '.dat')

with open(out_path, 'w') as f:
    for i in range(0, len(data), 4):
        word = int.from_bytes(data[i:i+4], 'little')
        f.write(f'{word:08x}\n')

print(f'{len(data)//4} words -> {out_path}')
