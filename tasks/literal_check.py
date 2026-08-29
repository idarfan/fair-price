#!/usr/bin/env python3
"""型別化前後的字面值比對（tasks/lessons.md 2026-08-29）。

用法：python3 tasks/literal_check.py <轉換前的 commit> <模組名稱...>
例：  python3 tasks/literal_check.py 77c504f ivAnalysis bullPutSpreads

型別註記不該改動任何數值常數或使用者可見字串。這支從 git HEAD 取出對應的 .js
原檔，跟轉換後的 .ts 比對數字與字串字面值的多重集合，抓出「順手改掉」的意外
（例如把 0.3989422820 寫成 1/sqrt(2pi) 的真值）。

差異不一定是錯：重構時本來就會移除死碼、合併重複字串。這支只負責把差異攤開來
讓人看，不自動判定對錯。
"""
import re
import subprocess
import sys
from collections import Counter

NUM = re.compile(r"(?<![\w.])\d+\.\d+(?![\w.])")
STR = re.compile(r"'([^'\\\n]{2,})'|\"([^\"\\\n]{2,})\"|`([^`\\\n$]{2,})`")


def literals(src: str) -> tuple[Counter, Counter]:
    src = re.sub(r"/\*.*?\*/", "", src, flags=re.S)
    src = re.sub(r"^\s*//.*$", "", src, flags=re.M)
    nums = Counter(NUM.findall(src))
    strs = Counter(m for groups in STR.findall(src) for m in groups if m)
    return nums, strs


def git_show(rev: str, path: str) -> str | None:
    r = subprocess.run(["git", "show", f"{rev}:{path}"],
                       capture_output=True, text=True)
    return r.stdout if r.returncode == 0 else None


def main(rev: str, names: list[str]) -> int:
    problems = 0
    for name in names:
        old = git_show(rev, f"app/frontend/behaviors/{name}.js")
        if old is None:
            print(f"— {name}: HEAD 沒有 .js 原檔，跳過")
            continue
        try:
            new = open(f"app/frontend/behaviors/{name}.ts").read()
        except FileNotFoundError:
            print(f"— {name}: 找不到 .ts")
            continue

        on, os_ = literals(old)
        nn, ns = literals(new)

        lost_nums = on - nn
        # 數值常數消失 = 可能被打錯或算式被改寫，一定要看
        if lost_nums:
            problems += 1
            print(f"\n⚠️  {name}: 原檔有、新檔沒有的數值 {dict(lost_nums)}")
            gained = nn - on
            if gained:
                print(f"    新檔多出來的數值 {dict(gained)}")

        lost_strs = {s: c for s, c in (os_ - ns).items()
                     if not s.startswith(("app/", "TODO")) and "稽核" not in s}
        if lost_strs:
            print(f"\n·  {name}: 原檔有、新檔沒有的字串（{len(lost_strs)} 個）")
            for s in list(lost_strs)[:8]:
                print(f"     {s[:70]!r}")
    print(f"\n數值有差異的檔案：{problems}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1], sys.argv[2:]))
