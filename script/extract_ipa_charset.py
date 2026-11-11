#!/usr/bin/env python3
"""
Phase J：從 VOCAB_CARDS 的 ipa 欄位程式化掃描實際使用的 IPA/拉丁字元，
寫入 leaps_ipa_charset.txt 供 subset_ipa_font.sh 使用。

文案（新增字卡）改動後重跑本腳本＋subset_ipa_font.sh 即可重建，不需手工列舉。

掃描範圍（2026-11-11 修正）：原本寫死 page_component.rb，VOCAB_CARDS 搬到
shared_constants.rb 後掃到 0 個字元，重建會讓術語字卡音標全部缺字。改成掃
leaps_recommendations/ 整個目錄的 `ipa: "…"`，掃不到任何音標就直接失敗；
並把目前子集字型已收錄的字併進來，重建只增不減（見 font_subset_guard.py）。
"""
import glob
import os
import re

from font_subset_guard import existing_chars

TARGET_GLOB = "app/components/leaps_recommendations/**/*.rb"
CURRENT_FONT = "vendor/assets/fonts/NotoSans-Regular-ipa-subset-v42.ttf"


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    ipa_values = []
    for path in sorted(glob.glob(os.path.join(root, TARGET_GLOB), recursive=True)):
        with open(path, encoding="utf-8") as f:
            ipa_values += re.findall(r'ipa: "(.*?)"', f.read())
    if not ipa_values:
        raise SystemExit(f"掃描範圍失效：{TARGET_GLOB} 裡找不到任何 ipa: \"…\"")

    scanned = set("".join(ipa_values))
    kept = existing_chars(os.path.join(root, CURRENT_FONT))
    charset = sorted(scanned | kept)

    out_path = os.path.join(root, "script", "leaps_ipa_charset.txt")
    with open(out_path, "w", encoding="utf-8") as f:
        f.write("".join(charset))

    print(f"音標欄位：{len(ipa_values)}　IPA 字元：{len(scanned)}"
          f"　沿用舊字型：{len(kept - scanned)}　總計：{len(charset)}")
    print(f"已寫入 {out_path}")


if __name__ == "__main__":
    main()
