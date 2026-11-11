#!/usr/bin/env python3
"""
LEAPS PDF 字型子集的共用工具（subset_font.sh／subset_ipa_font.sh 使用）。

1. existing_chars(font_path)：讀目前 repo 內子集字型的 cmap，回傳已收錄的字元。
   extract_*_charset.py 會把這些字併進新字元集，讓重建「只增不減」——
   文案改寫後就算某個字暫時不在原始碼裡，也不會從字型裡消失（2026-11-11 使用者裁示）。
2. verify：重建後比對舊字型、新字型、字元集，任一條件不成立就回傳非 0：
   - 新字型必須涵蓋舊字型的全部字元（不得縮水）
   - 字元集中「完整字型有收錄」的字元，新字型都要有
     （emoji、變體選擇符等完整字型本來就沒有的字元不算缺字）

用法：python3 font_subset_guard.py verify <舊字型> <新字型> <完整字型> <字元集檔>
"""
import sys

from fontTools.ttLib import TTFont


def cmap_of(path):
    return set(TTFont(path).getBestCmap())


def existing_chars(font_path):
    try:
        return {chr(c) for c in cmap_of(font_path)}
    except FileNotFoundError:
        return set()


def verify(old_font, new_font, full_font, charset_file):
    old = cmap_of(old_font)
    new = cmap_of(new_font)
    full = cmap_of(full_font)
    with open(charset_file, encoding="utf-8") as f:
        wanted = {ord(c) for c in f.read()}

    lost = sorted(old - new)
    missing = sorted((wanted & full) - new)
    not_in_full = sorted(wanted - full)

    print(f"舊字型 {len(old)} 字 → 新字型 {len(new)} 字（新增 {len(new - old)}）")
    if not_in_full:
        print(f"完整字型本身沒有、不列入檢查的字元：{len(not_in_full)} 個")
    ok = True
    if lost:
        ok = False
        print(f"失敗：新字型少了舊字型的 {len(lost)} 個字：" + "".join(chr(c) for c in lost))
    if missing:
        ok = False
        print(f"失敗：字元集有 {len(missing)} 個字沒進新字型：" + "".join(chr(c) for c in missing))
    if ok:
        print("檢查通過：舊字一個都沒少，字元集的字全部收錄")
    return 0 if ok else 1


if __name__ == "__main__":
    if len(sys.argv) == 6 and sys.argv[1] == "verify":
        sys.exit(verify(*sys.argv[2:]))
    print(__doc__)
    sys.exit(2)
