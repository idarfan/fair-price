#!/bin/bash
# 歐歐每日盤前報告
# 由 pm2 cron 每週一至五 13:00 UTC（= 美東夏令 09:00 EDT / 冬令 08:00 EST）自動執行

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
