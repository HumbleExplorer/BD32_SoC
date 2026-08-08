import os
import sys
import urllib.request

base = sys.argv[1] if len(sys.argv) > 1 else os.environ.get("RISCV_SPEC_DIR", "riscv-spec")
os.makedirs(base, exist_ok=True)

url = "https://docs.riscv.org/reference/home/index.html"
req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
data = urllib.request.urlopen(req, timeout=30).read()
print("fetched bytes:", len(data))
with open(os.path.join(base, "index.html"), "wb") as f:
    f.write(data)
print("saved index.html")
