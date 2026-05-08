#!/bin/bash
# IV 每日 ATM IV 快照
# pm2 cron: 30 4 * * 2-6（台灣時間 04:30 火〜土 = UTC 20:30 週一〜五，美股收盤後）

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
