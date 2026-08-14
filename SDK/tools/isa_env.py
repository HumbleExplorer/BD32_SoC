#!/usr/bin/env python3
"""
SDK/isa 测试环境同步工具（BD32）。

策略：
- SDK/isa/env 使用仓库内维护的 BD32 文件（link.ld / riscv_test.h / encoding.h），随仓库提交；
- SDK/isa/{rv32ui,rv32um,rv64ui,macros} 是可再生成的官方测试源码与宏（不入库），
  缺失时自动从 third_party/riscv-tests/isa 复制补齐。

被 build_riscv_tests.py 与 build_asm.py 共用。
"""

import os
import shutil
import sys

ISA_SUBDIRS = ("rv32ui", "rv32um", "rv64ui", "macros")


def default_riscv_tests(repo_root):
    return os.path.join(repo_root, "third_party", "riscv-tests")


def ensure_sdk_isa(repo_root, riscv_tests=None):
    """确保 SDK/isa 工作目录就绪；缺失的子目录从 riscv-tests 源码复制。"""
    sdk_isa = os.path.join(repo_root, "SDK", "isa")
    src_isa = os.path.join(riscv_tests or default_riscv_tests(repo_root), "isa")

    if not os.path.isdir(src_isa):
        sys.exit(
            "[ERROR] 未找到 riscv-tests 源码: %s\n"
            "  请先获取官方 riscv-tests：\n"
            "    git clone https://github.com/riscv/riscv-tests.git third_party/riscv-tests\n"
            "  或设置环境变量 RISCV_TESTS_SRC 指向已下载的副本。" % src_isa
        )

    env_h = os.path.join(sdk_isa, "env", "p", "riscv_test.h")
    if not os.path.isfile(env_h):
        sys.exit(
            "[ERROR] 缺少仓库内测试环境文件: %s\n"
            "  请确认 SDK/isa/env 已随仓库检出。" % env_h
        )

    os.makedirs(sdk_isa, exist_ok=True)
    copied = []
    for sub in ISA_SUBDIRS:
        dst = os.path.join(sdk_isa, sub)
        if not os.path.isdir(dst):
            shutil.copytree(os.path.join(src_isa, sub), dst)
            copied.append(sub)

    if copied:
        print("  [SDK/isa 同步] 已从 %s 复制: %s" % (src_isa, ", ".join(copied)))
    else:
        print("  [SDK/isa 已就绪]")


if __name__ == "__main__":
    ensure_sdk_isa(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
