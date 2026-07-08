#!/usr/bin/env python3
"""
Phase J (leaps-phase-j-vector-pdf-spec.md)：從 LEAPS 相關 Phlex/service 原始碼
程式化掃描實際使用的中文字元，寫入 leaps_pdf_charset.txt 供 subset_font.sh 使用。

文案改動後重跑本腳本＋subset_font.sh 即可重建字型子集，不需手工列舉字元。
"""
import re
import os

TARGETS = [
    "app/components/leaps_recommendations/page_component.rb",
    "app/services/leaps_recommendation_service.rb",
    "app/services/leaps_ranking_service.rb",
]

# 安全邊際：常見中文標點符號，即使目前原始碼未出現，文案微調也不必重跑就能顯示。
MARGIN_EXTRA = "「」『』（）【】《》〈〉、。，．：；！？…—～·＄％＃＆＠"

CJK_PATTERN = re.compile(r"[一-鿿　-〿＀-￯]")


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    all_text = ""
    for rel in TARGETS:
        path = os.path.join(root, rel)
        with open(path, encoding="utf-8") as f:
            all_text += f.read()

    cjk_chars = sorted(set(CJK_PATTERN.findall(all_text)))
    extra = sorted(set(MARGIN_EXTRA) - set(cjk_chars))
    full_charset = cjk_chars + extra

    out_path = os.path.join(root, "script", "leaps_pdf_charset.txt")
    with open(out_path, "w", encoding="utf-8") as f:
        f.write("".join(full_charset))

    print(f"掃描字元：{len(cjk_chars)}　安全邊際：{len(extra)}　總計：{len(full_charset)}")
    print(f"已寫入 {out_path}")


if __name__ == "__main__":
    main()
