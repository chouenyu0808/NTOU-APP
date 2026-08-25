"""
check.py — commit 前跑這一個指令就好。

三道關卡，順序是刻意的：**個資檢查放第一個**，因為那是唯一一種
「弄錯了就無法挽回」的失敗 —— 明文密碼一旦推上遠端，改密碼也救不回歷史紀錄。
測試紅了、lint 髒了都只是重跑一次的事。

用法：
    .venv\\Scripts\\python.exe check.py
    .venv\\Scripts\\python.exe check.py --quiet     # 只在失敗時輸出

掛成 git hook（在 ntou-app 目錄下）：
    New-Item -ItemType Directory -Force .git\\hooks
    # .git/hooks/pre-commit 內容：
    #   #!/bin/sh
    #   exec spike/.venv/Scripts/python.exe spike/check.py --quiet
"""
from __future__ import annotations

import _console  # noqa: F401  # 必須最先 import

import argparse
import re
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).parent
PYTHON = sys.executable


def run(name: str, args: list[str], quiet: bool) -> bool:
    result = subprocess.run(  # noqa: S603
        args, cwd=HERE, capture_output=True, text=True,
        encoding="utf-8", errors="replace", check=False,
    )
    ok = result.returncode == 0

    if ok and quiet:
        return True

    mark = "OK  " if ok else "失敗"
    print(f"[{mark}] {name}")
    if not ok:
        body = (result.stdout + result.stderr).strip()
        for line in body.splitlines()[-25:]:
            print(f"        {line}")
        print()
    return ok


def fixture_files() -> list[str]:
    """只檢查 fixtures/ 底下的 html —— callbacks/ 是 debug 用的，不進版控。"""
    return sorted(str(p) for p in (HERE / "fixtures").glob("*.html"))


# 會進版控的檔案裡不該出現的東西。
# fixture 檢查只看 fixtures/，但個資會跑到別的地方 ——
# 實際發生過：對外 IP 被抄進 scrub.py 的註解裡，跟著程式碼一起要上 GitHub。
TRACKED_PATTERNS = {
    "身分證字號": re.compile(r"\b[A-Z][12]\d{8}\b"),
    # 排掉私有網段和 scrub 用的佔位符
    "對外 IP": re.compile(r"\b(?!10\.|127\.|192\.168\.|0\.)(?:\d{1,3}\.){3}\d{1,3}\b"),
    "明文密碼": re.compile(r"""LoginPWD['"]?\s*[:=]\s*['"](?!REDACTED|你的密碼|\.\.\.)[^'"]{3,}"""),
}
# 這些是刻意寫死的假資料，不是外洩
ALLOWED = {"A123456789", "P@ssw0rd123", "SuperSecret123", "10.0.0.1", "0912-345-678"}


def scan_tracked_files(quiet: bool) -> bool:
    """掃描 git 會納入版控的每一個檔案 —— 不只是 fixtures/。"""
    listing = subprocess.run(
        ["git", "ls-files", "--cached", "--others", "--exclude-standard"],
        cwd=HERE.parent, capture_output=True, text=True, check=False,
    )
    if listing.returncode != 0:
        if not quiet:
            print("[跳過] 不是 git repo，tracked 檔案掃描略過")
        return True

    hits: list[str] = []
    for rel in listing.stdout.split():
        path = HERE.parent / rel
        try:
            text = path.read_text(encoding="utf-8")
        except (UnicodeDecodeError, OSError):
            continue
        for label, pat in TRACKED_PATTERNS.items():
            for m in pat.finditer(text):
                # 比對用「包含」而不是相等 —— 匹配到的是整段
                # `LoginPWD:'P@ssw0rd123`，不是單獨的值
                if any(a in m.group(0) for a in ALLOWED):
                    continue
                line = text[:m.start()].count("\n") + 1
                hits.append(f"[{label}] {rel}:{line}  {m.group(0)[:50]!r}")

    if hits:
        print("[失敗] tracked 檔案個資掃描")
        for h in hits:
            print(f"        {h}")
        print()
        return False
    if not quiet:
        print("[OK  ] tracked 檔案個資掃描")
    return True


def main() -> int:
    ap = argparse.ArgumentParser(description="commit 前的把關檢查")
    ap.add_argument("--quiet", action="store_true", help="只在失敗時輸出")
    args = ap.parse_args()

    files = fixture_files()
    if not files and not args.quiet:
        print("[跳過] fixtures/ 裡沒有 html，個資檢查略過")

    checks: list[tuple[str, list[str]]] = []
    if files:
        # 第一關：fixture 不能有明文密碼、學號、姓名、身分證、IP
        checks.append(("fixture 個資檢查", [PYTHON, "scrub.py", *files, "--check"]))
    checks += [
        ("pytest", [PYTHON, "-m", "pytest", "-q"]),
        ("ruff", [PYTHON, "-m", "ruff", "check", "."]),
    ]

    failed = [name for name, cmd in checks if not run(name, cmd, args.quiet)]
    if not scan_tracked_files(args.quiet):
        failed.append("tracked 檔案個資掃描")

    if failed:
        print(f"\n{len(failed)} 項未通過：{', '.join(failed)}", file=sys.stderr)
        if "fixture 個資檢查" in failed:
            print(
                "\n個資檢查沒過就**不要 commit**。先跑：\n"
                "    .venv\\Scripts\\python.exe scrub.py (ls fixtures\\*.html) "
                "--id 你的學號 --name 你的姓名",
                file=sys.stderr,
            )
        return 1

    if not args.quiet:
        print(f"\n全部通過（{len(checks)} 項）")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
