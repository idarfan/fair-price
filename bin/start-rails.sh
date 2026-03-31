#!/bin/bash
set -e

APP_DIR="/home/idarfan/fairprice"
PID_FILE="$APP_DIR/tmp/pids/server.pid"
HEALTH_URL="http://localhost:3003/up"
MAX_WAIT=30

# 清除 stale pid（異常終止後的防禦）
rm -f "$PID_FILE"

# 啟動 Rails（前景，讓 pm2 追蹤）
bundle exec rails server -p 3003 -b 0.0.0.0 &
RAILS_PID=$!

# 等待 Rails 通過 health check
echo "[start-rails] Waiting for Rails to be ready..."
for i in $(seq 1 $MAX_WAIT); do
  sleep 1
  if curl -sf "$HEALTH_URL" > /dev/null 2>&1; then
    echo "[start-rails] Rails is up (${i}s)"
    # 把控制權交回給 Rails 行程（pm2 追蹤此 PID）
    wait $RAILS_PID
    exit $?
  fi
done

echo "[start-rails] ERROR: Rails did not respond within ${MAX_WAIT}s"
kill "$RAILS_PID" 2>/dev/null
exit 1
