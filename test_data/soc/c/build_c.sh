#!/bin/bash
# ============================================================================
# build_c.sh — 构建「C 测试程序」(soc/c)
#
# 真正干活的是 SDK/tools/build.py：它编译 SDK/demos/<demo>，
# 自动产出 <demo>_itcm.mem / <demo>_dtcm.mem / <demo>.uartbin，
# 并同步到 test_data/soc/c/，供 soc_test 经 BootROM / DIRECT_LOAD 加载。
# （C 测试需要 BootROM：真实硬件里由 mrom 从 flash 载入 ITCM/DTCM；
#  仿真里 DIRECT_LOAD 直接预载那两个 .mem。）
#
# 用法：
#   ./build_c.sh coremark            # 构建单个（默认加 --newlib）
#   ./build_c.sh hello --newlib       # 显式带 --newlib
#   ./build_c.sh coremark --no-newlib-ish   # 不加 --newlib（用裸 libgcc）
#   ./build_c.sh all                 # 构建 SDK/demos/newlib 下全部
#   ./build_c.sh list                # 列出可用 demo
# ============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# soc/c -> up3 = Working/
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
# Windows .exe 工具（python）只认 Windows 风格路径；Git Bash 的 /d/... 它不认
REPO_ROOT_WIN="$(cygpath -w "$REPO_ROOT" | sed 's/\\/\//g')"
BUILD_PY="$REPO_ROOT_WIN/SDK/tools/build.py"
DEMO_BASE="$REPO_ROOT_WIN/SDK/demos"

PYBIN="D:/Python312/python.exe"

list_demos() {
    echo "Available demos (newlib):"
    ls -1 "$DEMO_BASE/newlib" 2>/dev/null
}

case "$1" in
    ""|-h|--help)
        sed -n '2,14p' "$0"
        ;;
    list)
        list_demos
        ;;
    all)
        for d in "$DEMO_BASE/newlib"/*/; do
            n="$(basename "$d")"
            echo "=== build_c: $n ==="
            "$PYBIN" "$BUILD_PY" "$DEMO_BASE/newlib/$n" --newlib
        done
        ;;
    *)
        name="$1"; shift
        # 默认加 --newlib（printf/malloc/stdio 需要）；用户已给则不再重复加
        if [[ " $* " == *" --newlib "* ]]; then
            "$PYBIN" "$BUILD_PY" "$DEMO_BASE/newlib/$name" "$@"
        else
            "$PYBIN" "$BUILD_PY" "$DEMO_BASE/newlib/$name" --newlib "$@"
        fi
        ;;
esac
