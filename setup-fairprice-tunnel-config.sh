#!/bin/bash
set -e

CONFIG_DIR="$HOME/.cloudflared"
CONFIG_FILE="$CONFIG_DIR/config.yml"
CRED_FILE="$CONFIG_DIR/9bed3d2b-8da8-490f-a88f-36b93a065f5d.json"

if [ ! -f "$CRED_FILE" ]; then
  echo "找不到憑證檔: $CRED_FILE"
  echo "請確認已經跑過 cloudflared tunnel create fairprice"
  exit 1
fi

cat > "$CONFIG_FILE" << EOF
tunnel: fairprice
credentials-file: $CRED_FILE

ingress:
  - hostname: fairprice-ohmy.com
    service: http://localhost:3003
  - service: http_status:404
EOF

echo "已寫入設定檔: $CONFIG_FILE"
echo ""
cat "$CONFIG_FILE"
echo ""
echo "接下來執行: cloudflared tunnel run fairprice"
