#!/usr/bin/env python3
"""
Phase J (leaps-phase-j-vector-pdf-spec.md)：從 LEAPS PDF 文案的原始碼程式化掃描
實際使用的字元，寫入 leaps_pdf_charset.txt 供 subset_font.sh 使用。

文案改動後重跑本腳本＋subset_font.sh 即可重建字型子集，不需手工列舉字元。

掃描範圍（2026-11-11 修正）：原本寫死 3 個檔案，page_component.rb 拆成
leaps_recommendations/ 底下多個模組後，大部分文案已不在清單內，重建會從 790 字
掉到 404 字。改成用目錄比對，並涵蓋 PDF 文案的所有來源：
- app/components/leaps_recommendations/ 整個目錄（含 pdf_export.rb、shared_constants.rb、formatting.rb）
- LEAPS 推薦／排行／最划算／Options Flow 服務（推薦理由與 flow 摘要文字）
- app/models/leaps_table_columns.rb（排行表欄名，PDF 表頭）
- app/assets/javascripts/leaps_recommendations/vector_pdf.js（PDF 端自己寫的字串）
另外把目前子集字型已收錄的字併進來，重建只增不減（見 font_subset_guard.py）。
"""
import glob
import os
import re

from font_subset_guard import existing_chars

TARGET_GLOBS = [
    "app/components/leaps_recommendations/**/*.rb",
    "app/services/leaps_recommendation_service.rb",
    "app/services/leaps_ranking_service.rb",
    "app/services/leaps_best_value_service.rb",
    "app/services/leaps_options_flow_panel_service.rb",
    "app/services/options_flow_classifier_service.rb",
    "app/models/leaps_table_columns.rb",
    "app/assets/javascripts/leaps_recommendations/vector_pdf.js",
]

CURRENT_FONT = "vendor/assets/fonts/NotoSansTC-Regular-subset-v39.ttf"

# 安全邊際：常見中文標點符號，即使目前原始碼未出現，文案微調也不必重跑就能顯示。
MARGIN_EXTRA = "「」『』（）【】《》〈〉、。，．：；！？…—～·＄％＃＆＠"

# 抓「任何非 ASCII 字元」，不要窄化成 CJK 統一表意文字區塊。
# 教訓（2026-07-08）：原本只抓 [一-鿿　-〿＀-￯]（CJK Unified Ideographs +
# 全形符號），漏掉一般標點符號區塊（EN DASH – U+2013、EM DASH — U+2014）、
# IPA 音標字元、數學符號等——字型子集缺這些字形時 pdftotext 會直接跳過該
# 字元（不是印出方框），比豆腐字更隱蔽，肉眼與逐字比對都可能漏看。
NON_ASCII_PATTERN = re.compile(r"[^\x00-\x7F]")


def target_files(root):
    files = []
    for pattern in TARGET_GLOBS:
        matched = sorted(glob.glob(os.path.join(root, pattern), recursive=True))
        if not matched:
            # 路徑失效要大聲失敗，不能默默少掃（這支腳本就是這樣壞掉的）
            raise SystemExit(f"掃描範圍失效：{pattern} 沒有對到任何檔案")
        files.extend(matched)
    return files


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    files = target_files(root)
    all_text = ""
    for path in files:
        with open(path, encoding="utf-8") as f:
            all_text += f.read()

    scanned = set(NON_ASCII_PATTERN.findall(all_text))
    kept = {c for c in existing_chars(os.path.join(root, CURRENT_FONT)) if ord(c) > 0x7F}
    extra = set(MARGIN_EXTRA)
    full_charset = sorted(scanned | kept | extra)

    out_path = os.path.join(root, "script", "leaps_pdf_charset.txt")
    with open(out_path, "w", encoding="utf-8") as f:
        f.write("".join(full_charset))

    print(f"掃描檔案：{len(files)}　掃描字元：{len(scanned)}"
          f"　沿用舊字型：{len(kept - scanned)}　安全邊際：{len(extra - scanned - kept)}"
          f"　總計：{len(full_charset)}")
    print(f"已寫入 {out_path}")


if __name__ == "__main__":
    main()
