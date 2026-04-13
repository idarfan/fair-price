#!/bin/bash
# 歐歐每日盤前報告
# 由 pm2 cron 每週一至五 21:00 台灣時間（= 美東夏令 09:00 EDT，美股盤前 30 分鐘）
# ⚠️  冬令時間（EST，約 11 月初至 3 月中）美股改 22:30 開盤，屆時需手動改為 22:00

set -e

export HOME=/home/idarfan
export RBENV_ROOT="$HOME/.rbenv"
export PATH="$RBENV_ROOT/shims:$RBENV_ROOT/bin:/usr/bin:/bin"

eval "$(rbenv init -)"

cd /home/idarfan/fairprice

# 載入 .env（確保 GROQ_API_KEY、TELEGRAM_BOT_TOKEN 等可用）
if [ -f .env ]; then
  set -a
  source .env
  set +a
fi

exec bundle exec rake ouou:pre_market
