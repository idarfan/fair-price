#!/bin/bash
# 歐歐每日盤前報告
# pm2 cron: 0 21,22 * * 1-5（台灣時間 21:00 & 22:00，週一至五）
# 腳本自動偵測美東時間（EDT/EST 自動切換），僅在紐約時間 09:00–09:04 執行。
# 夏令（EDT, UTC-4）: 21:00 TWN = 09:00 EDT → 執行
# 冬令（EST, UTC-5）: 22:00 TWN = 09:00 EST → 執行

set -e

export HOME=/home/idarfan
export RBENV_ROOT="$HOME/.rbenv"
export PATH="$RBENV_ROOT/shims:$RBENV_ROOT/bin:/usr/bin:/bin"

# ── DST 自動偵測：只在紐約時間 09:00–09:04 執行 ──────────────────
NY_HOUR=$(TZ=America/New_York date +%H)
NY_MIN=$(TZ=America/New_York date +%M)

if [[ "$NY_HOUR" != "09" || "$NY_MIN" -gt 4 ]]; then
  echo "[ouou-pre-market] 跳過：紐約時間 ${NY_HOUR}:${NY_MIN}（非盤前窗口）"
  exit 0
fi

echo "[ouou-pre-market] 啟動：紐約時間 ${NY_HOUR}:${NY_MIN}（$(TZ=America/New_York date +%Z)）"

eval "$(rbenv init -)"

cd /home/idarfan/fairprice

# 載入 .env（確保 GROQ_API_KEY、TELEGRAM_BOT_TOKEN 等可用）
if [ -f .env ]; then
  set -a
  source .env
  set +a
fi

exec bundle exec rake ouou:pre_market
