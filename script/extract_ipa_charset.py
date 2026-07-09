#!/usr/bin/env python3
"""
Phase J：從 VOCAB_CARDS 的 ipa 欄位程式化掃描實際使用的 IPA/拉丁字元，
寫入 leaps_ipa_charset.txt 供 subset_ipa_font.sh 使用。

文案（新增字卡）改動後重跑本腳本＋subset_ipa_font.sh 即可重建，不需手工列舉。
"""
import re
import os

TARGET = "app/components/leaps_recommendations/page_component.rb"


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    with open(os.path.join(root, TARGET), encoding="utf-8") as f:
        content = f.read()

    ipa_values = re.findall(r'ipa: "(.*?)"', content)
    charset = sorted(set("".join(ipa_values)))

    out_path = os.path.join(root, "script", "leaps_ipa_charset.txt")
    with open(out_path, "w", encoding="utf-8") as f:
        f.write("".join(charset))

    print(f"IPA 字元：{len(charset)}")
    print(f"已寫入 {out_path}")


if __name__ == "__main__":
    main()
