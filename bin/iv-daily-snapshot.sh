#!/bin/bash
# IV 每日 ATM IV 快照
# pm2 cron: 30 20 * * 1-5（UTC，收盤後 16:30 ET = 20:30 UTC；pm2 daemon 必須以 TZ=UTC 啟動）

set -e

export HOME=/home/idarfan
export RBENV_ROOT="$HOME/.rbenv"
export PATH="$RBENV_ROOT/shims:$RBENV_ROOT/bin:/usr/bin:/bin"

eval "$(rbenv init -)"
cd /home/idarfan/fairprice

if [ -f .env ]; then
  set -a; source .env; set +a
fi

exec bundle exec rake iv:daily_snapshot
