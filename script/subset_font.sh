#!/usr/bin/env bash
# Phase J (leaps-phase-j-vector-pdf-spec.md)：重建 LEAPS PDF 向量匯出用的
# Noto Sans TC 字型子集。文案改動後重跑本腳本即可重建，不需手工列舉字元。
#
# 來源字型：Google Fonts CDN, Noto Sans TC Regular, version 2.004-H2 (OFL 1.1)
#   https://fonts.gstatic.com/s/notosanstc/v39/-nFuOG829Oofr2wohFbTp9ifNAn722rq0MXz76Cy_Co.ttf
# 完整字型不 commit 進 repo（約 7MB）；本腳本會下載到 tmp 再 subset。
#
# 依賴：pyftsubset（fonttools）、curl
#
# 2026-11-11：掃描範圍改為整個 leaps_recommendations/ 目錄＋PDF 文案來源（見
# extract_leaps_charset.py），且沿用舊字型已收錄的字，重建只增不減。重建後由
# font_subset_guard.py 檢查；新字型少了任何舊字、或掃到的字沒收進去，就還原舊字型並失敗。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FONT_SRC_URL="https://fonts.gstatic.com/s/notosanstc/v39/-nFuOG829Oofr2wohFbTp9ifNAn722rq0MXz76Cy_Co.ttf"
FULL_FONT="/tmp/NotoSansTC-Regular-full.ttf"
OUT_FONT="$ROOT/vendor/assets/fonts/NotoSansTC-Regular-subset-v39.ttf"
CHARSET_FILE="$ROOT/script/leaps_pdf_charset.txt"

echo "== Phase J font subset rebuild =="

echo "[1/3] 重新掃描 LEAPS 文案字元集..."
python3 "$ROOT/script/extract_leaps_charset.py"

echo "[2/3] 取得完整字型（快取於 $FULL_FONT）..."
if [ ! -f "$FULL_FONT" ]; then
  curl -sL "$FONT_SRC_URL" -o "$FULL_FONT"
fi
FULL_SIZE=$(stat -c%s "$FULL_FONT")
echo "  完整字型大小：$FULL_SIZE bytes"

echo "[3/3] 執行 pyftsubset..."
mkdir -p "$ROOT/vendor/assets/fonts"

CHARSET="$(cat "$CHARSET_FILE")"

OLD_FONT="$(mktemp --suffix=.ttf)"
trap 'rm -f "$OLD_FONT"' EXIT
cp "$OUT_FONT" "$OLD_FONT"

pyftsubset "$FULL_FONT" \
  --output-file="$OUT_FONT" \
  --unicodes="U+0020-007E" \
  --text="$CHARSET" \
  --layout-features='*' \
  --glyph-names \
  --symbol-cmap \
  --legacy-cmap \
  --notdef-glyph \
  --notdef-outline \
  --recommended-glyphs \
  --no-hinting \
  --desubroutinize \
  --name-IDs='*' \
  --name-legacy \
  --name-languages='*'

echo "[檢查] 新舊字型比對..."
if ! python3 "$ROOT/script/font_subset_guard.py" verify "$OLD_FONT" "$OUT_FONT" "$FULL_FONT" "$CHARSET_FILE"; then
  cp "$OLD_FONT" "$OUT_FONT"
  echo "已還原舊字型：$OUT_FONT" >&2
  exit 1
fi

SUBSET_SIZE=$(stat -c%s "$OUT_FONT")
RATIO=$(python3 -c "print(f'{$SUBSET_SIZE / $FULL_SIZE * 100:.1f}')")

echo ""
echo "== 完成 =="
echo "完整字型：$FULL_SIZE bytes"
echo "子集字型：$SUBSET_SIZE bytes（${RATIO}%）"
echo "輸出：$OUT_FONT"
