#!/usr/bin/env bash
# Phase J：重建術語字卡 IPA 音標用的 Noto Sans（拉丁字型）子集。
# Noto Sans TC 本身不含 IPA Extensions 區塊字元（ɪ/ɛ/ə/ʊ/ˈ/ː 等），
# 音標改用第二個字型獨立嵌入，PDF 渲染時逐段切換字型畫同一行文字。
#
# 來源字型：Google Fonts CDN, Noto Sans Regular, version 2.015 (OFL 1.1)
#   https://fonts.gstatic.com/s/notosans/v42/o-0mIpQlx3QUlC5A4PNB6Ryti20_6n1iPHjcz6L1SoM-jCpoiyD9A99d.ttf
# 完整字型不 commit 進 repo；本腳本會下載到 tmp 再 subset。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FONT_SRC_URL="https://fonts.gstatic.com/s/notosans/v42/o-0mIpQlx3QUlC5A4PNB6Ryti20_6n1iPHjcz6L1SoM-jCpoiyD9A99d.ttf"
FULL_FONT="/tmp/NotoSans-Regular-full.ttf"
OUT_FONT="$ROOT/vendor/assets/fonts/NotoSans-Regular-ipa-subset-v42.ttf"
CHARSET_FILE="$ROOT/script/leaps_ipa_charset.txt"

echo "== Phase J IPA font subset rebuild =="

echo "[1/3] 重新掃描 VOCAB_CARDS IPA 字元集..."
python3 "$ROOT/script/extract_ipa_charset.py"

echo "[2/3] 取得完整字型（快取於 $FULL_FONT）..."
if [ ! -f "$FULL_FONT" ]; then
  curl -sL "$FONT_SRC_URL" -o "$FULL_FONT"
fi
FULL_SIZE=$(stat -c%s "$FULL_FONT")
echo "  完整字型大小：$FULL_SIZE bytes"

echo "[3/3] 執行 pyftsubset..."
mkdir -p "$ROOT/vendor/assets/fonts"

pyftsubset "$FULL_FONT" \
  --output-file="$OUT_FONT" \
  --text-file="$CHARSET_FILE" \
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

SUBSET_SIZE=$(stat -c%s "$OUT_FONT")

echo ""
echo "== 完成 =="
echo "完整字型：$FULL_SIZE bytes"
echo "子集字型：$SUBSET_SIZE bytes"
echo "輸出：$OUT_FONT"
