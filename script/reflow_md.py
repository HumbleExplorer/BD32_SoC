#!/usr/bin/env python3
"""reflow_md.py — Markdown 段落重排：一段话一行（渲染器流式换行），结构元素保留

保留不动（原样逐行）：
  - 围栏代码块（``` ... ```）内部
  - 表格行（以 | 开头）
  - 标题（# 开头）、引用（> 开头）、图片行（![ 开头）
  - 纯链接/裸 HTML 行（< 开头）
  - 4 空格及以上缩进的行（缩进代码块，保守保护）
合并规则：
  - 连续普通文本行合并为一行
  - 列表项（- / * / 数字.）起新行；其缩进延续行（2~3 空格）并入该项
  - 拼接时：行尾与行首都是 ASCII 字母数字/右括号-左括号组合则补一个空格，否则直接连（中文）
一次性迁移工具，用完可删。
"""
import argparse
import os
import re

LIST_RE = re.compile(r"^(\s*)([-*]|\d+\.)\s+")
ASCII_END = re.compile(r"[A-Za-z0-9_\)\]%>]$")
ASCII_START = re.compile(r"^[A-Za-z0-9_\(\[<&`]")
CJK = re.compile(r"[\u4e00-\u9fff]")


def join_lines(buf):
    if not buf:
        return []
    out = buf[0]
    for nxt in buf[1:]:
        nxt = nxt.lstrip()
        # 原断行处的隐含空格：英文词/数字 与 中文 任意一侧相邻时补一个空格，
        # 双英文词之间恒补；中文标点衔接（——、：等）不补
        a_end = out[-1] if out else ""
        b_start = nxt[0] if nxt else ""
        if (ASCII_END.search(a_end) and ASCII_START.match(b_start)) \
                or (ASCII_END.search(a_end) and CJK.match(b_start)) \
                or (CJK.search(a_end) and ASCII_START.match(b_start)):
            out += " " + nxt
        else:
            out += nxt
    return [out]


def reflow(path, apply):
    with open(path, encoding="utf-8") as f:
        src = f.read()
    lines = src.split("\n")
    out = []
    buf = []          # 当前待合并段落
    in_fence = False
    changed = 0

    def flush():
        nonlocal changed
        merged = join_lines(buf)
        if merged != buf:
            changed += 1
        out.extend(merged)
        buf.clear()

    for ln in lines:
        s = ln.strip()
        if s.startswith("```"):
            flush()
            out.append(ln)
            in_fence = not in_fence
            continue
        if in_fence:
            out.append(ln)
            continue
        buf_is_list = bool(buf) and bool(LIST_RE.match(buf[0]))
        buf_indent = (len(buf[0]) - len(buf[0].lstrip())) if buf else 0
        indent = len(ln) - len(ln.lstrip())
        # 4 空格行：列表延续则合并；否则按缩进代码块保守保护
        if ln.startswith("    ") and not (buf_is_list and indent >= 2):
            flush()
            out.append(ln)
            continue
        if (not s or s.startswith("#") or s.startswith(">") or s.startswith("|")
                or s.startswith("![") or s.startswith("<")):
            flush()
            out.append(ln)
            continue
        m = LIST_RE.match(ln)
        if m:
            # 带列表标记的行一律起新项（flush 前一段）；嵌套层级由原缩进保留。
            # 同级"懒延续"只可能是无标记的缩进文本行，走下方普通文本分支。
            flush()
            buf.append(ln.rstrip())
            continue
        # 普通文本行
        if buf_is_list and indent >= 2:
            buf.append(s)  # 列表项的缩进延续行（2~4 空格）
        else:
            buf.append(ln.rstrip())
    flush()

    result = "\n".join(out)
    if result != src:
        if apply:
            with open(path, "w", encoding="utf-8", newline="\n") as f:
                f.write(result)
        return True, changed
    return False, 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("paths", nargs="+")
    ap.add_argument("--apply", action="store_true")
    args = ap.parse_args()
    # 路径安全：只允许处理仓库子树内的 .md（防 ../ 逃逸写出仓库外）
    repo = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    for p in args.paths:
        rp = os.path.realpath(p)
        if not (rp == repo or rp.startswith(repo + os.sep)) or not rp.endswith(".md"):
            print("[SKIP] 仓库外或非 .md：%s" % p)
            continue
        ch, n = reflow(rp, args.apply)
        print("[%s] %s（%d 个段落被合并）" % ("APPLY" if args.apply else "DRY", p, n))


if __name__ == "__main__":
    main()
