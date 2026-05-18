#!/bin/bash
# IV 盤中 30 分鐘 Skew 快照
# pm2 cron: */30 * * * 1-5（CST 平日全天；rake task 內部 guard 跳過非交易時段）
# 注意：pm2 以系統時區 CST (UTC+8) 解析 cron，不能直接用 UTC 表達式
# 市場時段 ET 09:30-16:00 = UTC 13:30-20:00 = CST 21:30-04:00（跨午夜），故改用全天+內部 guard

set -e

export HOME=/home/idarfan
export RBENV_ROOT="$HOME/.rbenv"
export PATH="$RBENV_ROOT/shims:$RBENV_ROOT/bin:/usr/bin:/bin"

eval "$(rbenv init -)"
cd /home/idarfan/fairprice

if [ -f .env ]; then
  set -a; source .env; set +a
fi

exec bundle exec rake iv:skew_intraday_snapshot
