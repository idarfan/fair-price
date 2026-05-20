#!/bin/bash
# 歐歐每日盤前報告 — 迴圈模式
# pm2 autorestart: true，crash 後自動重啟
# 每 55 秒檢查一次紐約時間，僅在 09:00–09:04 ET 執行。

export HOME=/home/idarfan
export RBENV_ROOT="$HOME/.rbenv"
export PATH="$RBENV_ROOT/shims:$RBENV_ROOT/bin:/usr/bin:/bin"

eval "$(rbenv init -)"

cd /home/idarfan/fairprice

if [ -f .env ]; then
  set -a
  source .env
  set +a
fi

while true; do
  NY_HOUR=$(TZ=America/New_York date +%H)
  NY_MIN=$(TZ=America/New_York date +%M)

  NY_DOW=$(TZ=America/New_York date +%u)   # 1=週一 … 7=週日

  if [[ "$NY_DOW" -le 5 && "$NY_HOUR" == "09" && $((10#$NY_MIN)) -le 4 ]]; then
    echo "[ouou-pre-market] 啟動：紐約時間 ${NY_HOUR}:${NY_MIN}（$(TZ=America/New_York date +%Z)）"
    bundle exec rake ouou:pre_market || echo "[ouou-pre-market] ❌ rake 失敗，繼續迴圈"
    # 送完後多睡 5 分鐘，避免同窗口重複執行
    sleep 300
  else
    echo "[ouou-pre-market] 跳過：紐約時間 ${NY_HOUR}:${NY_MIN}（非盤前窗口）"
    sleep 55
  fi
done
