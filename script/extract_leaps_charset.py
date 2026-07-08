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

# 抓「任何非 ASCII 字元」，不要窄化成 CJK 統一表意文字區塊。
# 教訓（2026-07-08）：原本只抓 [一-鿿　-〿＀-￯]（CJK Unified Ideographs +
# 全形符號），漏掉一般標點符號區塊（EN DASH – U+2013、EM DASH — U+2014）、
# IPA 音標字元、數學符號等——字型子集缺這些字形時 pdftotext 會直接跳過該
# 字元（不是印出方框），比豆腐字更隱蔽，肉眼與逐字比對都可能漏看。
NON_ASCII_PATTERN = re.compile(r"[^\x00-\x7F]")


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    all_text = ""
    for rel in TARGETS:
        path = os.path.join(root, rel)
        with open(path, encoding="utf-8") as f:
            all_text += f.read()

    scanned = sorted(set(NON_ASCII_PATTERN.findall(all_text)))
    extra = sorted(set(MARGIN_EXTRA) - set(scanned))
    full_charset = scanned + extra

    out_path = os.path.join(root, "script", "leaps_pdf_charset.txt")
    with open(out_path, "w", encoding="utf-8") as f:
        f.write("".join(full_charset))

    print(f"掃描字元：{len(scanned)}　安全邊際：{len(extra)}　總計：{len(full_charset)}")
    print(f"已寫入 {out_path}")


if __name__ == "__main__":
    main()
