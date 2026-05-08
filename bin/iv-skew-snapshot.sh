#!/bin/bash
# IV 每日 25-delta Skew 快照
# pm2 cron: 45 4 * * 2-6（台灣時間 04:45 火〜土 = UTC 20:45 週一〜五，美股收盤後）

set -e

export HOME=/home/idarfan
export RBENV_ROOT="$HOME/.rbenv"
export PATH="$RBENV_ROOT/shims:$RBENV_ROOT/bin:/usr/bin:/bin"

eval "$(rbenv init -)"
cd /home/idarfan/fairprice

if [ -f .env ]; then
  set -a; source .env; set +a
fi

exec bundle exec rake iv:skew_snapshot
