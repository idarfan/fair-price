#!/bin/bash
set -e

CONFIG_DIR="$HOME/.cloudflared"
CONFIG_FILE="$CONFIG_DIR/config.yml"

if [ ! -f "$CONFIG_FILE" ]; then
  echo "找不到設定檔: $CONFIG_FILE"
  echo "請先完成 tunnel 建立與 config.yml 設定"
  exit 1
fi

# 1. 確保 protocol: http2 有寫進 config.yml（避免預設用 QUIC 卡住）
if grep -q "^protocol:" "$CONFIG_FILE"; then
  echo "config.yml 已有 protocol 設定，跳過"
else
  echo "protocol: http2" >> "$CONFIG_FILE"
  echo "已加入 protocol: http2 到 $CONFIG_FILE"
fi

echo ""
echo "===== 目前 config.yml 內容 ====="
cat "$CONFIG_FILE"
echo "================================"
echo ""

# 2. 確認 pm2 是否已安裝
if ! command -v pm2 &> /dev/null; then
  echo "找不到 pm2，請先安裝： npm install -g pm2"
  exit 1
fi

# 3. 如果已經有同名 process，先移除避免重複掛載
if pm2 describe fairprice-tunnel &> /dev/null; then
  echo "偵測到已存在的 fairprice-tunnel process，先移除舊的 ..."
  pm2 delete fairprice-tunnel
fi

# 4. 用 pm2 啟動 cloudflared tunnel
echo "啟動 cloudflared tunnel（pm2 管理）..."
pm2 start cloudflared --name fairprice-tunnel -- tunnel run fairprice

# 5. 存檔目前 process list，供開機還原用
pm2 save

echo ""
echo "===== pm2 process 清單 ====="
pm2 list
echo "============================"
echo ""

# 6. 檢查 pm2 startup 是否已設定過（開機自動復原機制）
if pm2 startup 2>&1 | grep -q "already"; then
  echo "pm2 startup 似乎已設定過，開機會自動還原 process。"
else
  echo "⚠️ 上面 pm2 startup 印出的指令，若你之前沒設定過，"
  echo "⚠️ 請複製那行指令貼到終端機執行一次（通常需要 sudo），"
  echo "⚠️ 這樣開機才會自動把 fairprice-tunnel 和其他 pm2 process 一起拉起來。"
fi

echo ""
echo "設定完成。檢查指令： pm2 status"
echo "查看 log： pm2 logs fairprice-tunnel"
