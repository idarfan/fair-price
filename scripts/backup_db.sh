#!/usr/bin/env bash
# ============================================================
#  FairPrice — 資料庫備份腳本
#  每日由 pm2 自動執行，保留最近 7 份備份
#  手動執行：bash scripts/backup_db.sh
# ============================================================
set -euo pipefail

BACKUP_DIR="${HOME}/fairprice-backups"
DB_NAME="fairprice_development"
DB_USER="${DB_USER:-idarfan}"
KEEP_DAYS=7

mkdir -p "$BACKUP_DIR"

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_FILE="${BACKUP_DIR}/${DB_NAME}_${TIMESTAMP}.sql.gz"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] 開始備份 ${DB_NAME}..."

# pg_dump 壓縮輸出
PGPASSWORD="${DB_PASSWORD:-}" pg_dump \
  -h 127.0.0.1 \
  -U "$DB_USER" \
  "$DB_NAME" \
  | gzip > "$BACKUP_FILE"

# 驗證備份非空（pg_dump 失敗時 gzip 仍會建立 0B 空檔）
if [[ ! -s "$BACKUP_FILE" ]]; then
  rm -f "$BACKUP_FILE"
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] 備份失敗或空檔，已刪除 ${BACKUP_FILE}" >&2
  exit 1
fi

SIZE=$(du -sh "$BACKUP_FILE" | cut -f1)
echo "[$(date '+%Y-%m-%d %H:%M:%S')] 備份完成：${BACKUP_FILE}（${SIZE}）"

# 清除 0B 殘留檔（防禦性清理）
find "$BACKUP_DIR" -name "*.sql.gz" -size 0 -delete 2>/dev/null

# 清除超過 KEEP_DAYS 天的舊備份
find "$BACKUP_DIR" -name "${DB_NAME}_*.sql.gz" -mtime "+${KEEP_DAYS}" -delete
REMAINING=$(find "$BACKUP_DIR" -name "${DB_NAME}_*.sql.gz" | wc -l)
echo "[$(date '+%Y-%m-%d %H:%M:%S')] 保留 ${REMAINING} 份備份（超過 ${KEEP_DAYS} 天自動刪除）"
