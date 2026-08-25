"""
conftest.py — 讓 pytest 的輸出在 Windows 上不要變亂碼。

pytest 的 terminal writer 在啟動時就抓住 sys.stdout，所以要在這裡（最早被 import
的地方）就把編碼改掉，光靠各模組自己 import _console 是來不及的。
"""
import _console  # noqa: F401
