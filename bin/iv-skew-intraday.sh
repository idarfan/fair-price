#!/bin/bash
# IV 盤中 30 分鐘 Skew 快照
# pm2 cron: */30 13-20 * * 1-5（UTC，覆蓋 ET 09:00-16:30，市場時段由 rake task 內部再過濾）

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
