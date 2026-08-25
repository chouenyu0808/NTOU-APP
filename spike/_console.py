"""
_console.py — Windows 主控台編碼修正。每支 CLI 都要在最上面 import。

Windows 的 Python 預設把 stdout 設成 cp950（Big5）。兩個後果：
  1. 輸出 UTF-8 的終端機看到的全是亂碼
  2. 遇到 Big5 編不出來的字（罕用字姓名、部分課名）直接 UnicodeEncodeError 崩掉

第 2 點才是真的麻煩 —— 會在抓資料抓到一半炸掉。
"""
from __future__ import annotations

import sys


def force_utf8() -> None:
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(encoding="utf-8", errors="replace")
        except (AttributeError, ValueError):
            pass  # 被重導向或包起來時可能沒有 reconfigure


force_utf8()
