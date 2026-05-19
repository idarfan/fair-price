#!/bin/bash
# IV 盤中 30 分鐘 Skew 快照
# pm2 cron: */30 13-20 * * 1-5（UTC，覆蓋 ET 09:00-16:00；pm2 daemon 必須以 TZ=UTC 啟動）
# rake task 內部再過濾非交易時段（開盤前 09:00-09:30 與非交易日）

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
