#!/bin/bash
set -e

# 對外服務(fairprice-ohmy.com tunnel)必須跑 production 模式,否則會洩漏
# Rails debug 錯誤頁(含程式碼路徑與 stack trace)給任何打錯路徑的訪客。
# 釘死在啟動腳本本身,不依賴 pm2 環境變數快取。
export RAILS_ENV=production

APP_DIR="/home/idarfan/fairprice"
PID_FILE="$APP_DIR/tmp/pids/server.pid"
HEALTH_URL="http://localhost:3003/up"
MAX_WAIT=30

# pm2 daemon 可能快取著舊的環境變數(daemon 啟動當下捕捉到的環境,跟
# .env 檔案內容脫鉤,pm2 restart --update-env 也救不回來,因為 daemon
# 用的是自己長駐的環境,不是下指令當下那個 shell 的環境)。這裡強制用
# .env 覆蓋任何繼承來的同名變數,確保 .env 永遠是唯一真相來源。
set -a
source "$APP_DIR/.env"
set +a

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
