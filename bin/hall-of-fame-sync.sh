#!/bin/bash
# 投資名人堂每日同步（House 索引 → 解析 pending PDF → 期權分析）
# pm2 cron: 30 0 * * *（UTC，= 台北 08:30；pm2 daemon 必須以 TZ=UTC 啟動）

set -e

export HOME=/home/idarfan
export RBENV_ROOT="$HOME/.rbenv"
export PATH="$RBENV_ROOT/shims:$RBENV_ROOT/bin:/usr/bin:/bin"

eval "$(rbenv init -)"
cd /home/idarfan/fairprice

if [ -f .env ]; then
  set -a; source .env; set +a
fi

exec bundle exec rake hall_of_fame:sync_house
