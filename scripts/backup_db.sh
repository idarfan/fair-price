#!/usr/bin/env bash
# ============================================================
#  FairPrice — 資料庫備份腳本
#  每日由 pm2 自動執行（cron restart: 0 22 * * *），保留最近 7 份備份
#  手動執行：bash scripts/backup_db.sh
#
#  備份會同時寫入兩個位置：
#    1. ~/fairprice-backups/              （本機，保留 7 天）
#    2. Windows 桌面 fairprice backup/    （異地保存，只新增不刪除）
# ============================================================
set -euo pipefail

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKUP_DIR="${HOME}/fairprice-backups"
WIN_MIRROR_DIR="/mnt/c/Users/mrida/Desktop/fairprice backup"
WIN_DESKTOP="/mnt/c/Users/mrida/Desktop"
DB_NAME="fairprice_development"
KEEP_DAYS=7

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

# ------------------------------------------------------------
# 讀取 .env 取得 DB_PASSWORD
# （舊版少了這段，PGPASSWORD 永遠是空的，pg_dump 會轉去互動式要密碼而失敗）
# ------------------------------------------------------------
if [[ -f "${APP_DIR}/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "${APP_DIR}/.env"
  set +a
fi

DB_USER="${DB_USER:-idarfan}"
DB_HOST="${DB_HOST:-127.0.0.1}"
DB_PORT="${DB_PORT:-5432}"

mkdir -p "$BACKUP_DIR"

# ------------------------------------------------------------
# 等待 PostgreSQL 就緒
# （開機後 pm2 可能比 postgres 早起來，會噴 "the database system is starting up"）
# ------------------------------------------------------------
for attempt in 1 2 3 4 5; do
  if pg_isready -h "$DB_HOST" -p "$DB_PORT" -q; then
    break
  fi
  if [[ $attempt -eq 5 ]]; then
    log "PostgreSQL 未就緒（${DB_HOST}:${DB_PORT}），放棄備份" >&2
    exit 1
  fi
  log "PostgreSQL 未就緒，10 秒後重試（${attempt}/5）"
  sleep 10
done

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_FILE="${BACKUP_DIR}/${DB_NAME}_${TIMESTAMP}.sql.gz"

log "開始備份 ${DB_NAME}..."

# -w：絕不互動式詢問密碼，缺密碼就直接失敗（避免像舊版那樣卡在 Password: 提示）
# 用 if 包住，讓 pipefail 觸發時仍能走到底下的清理與錯誤回報
if ! PGPASSWORD="${DB_PASSWORD:-}" pg_dump -w \
      -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" "$DB_NAME" \
      2>>"${BACKUP_DIR}/.last_error.log" | gzip > "$BACKUP_FILE"; then
  rm -f "$BACKUP_FILE"
  log "pg_dump 失敗，詳見 ${BACKUP_DIR}/.last_error.log" >&2
  exit 1
fi

# ------------------------------------------------------------
# 完整性驗證
# 舊版只用 [[ ! -s ]] 擋 0 bytes，但 gzip 失敗會產生 20 bytes 的「空壓縮檔」，
# 過得了檢查、留在目錄裡冒充成功的備份。改成驗 pg_dump 的結尾標記。
# ------------------------------------------------------------
if ! gzip -t "$BACKUP_FILE" 2>/dev/null; then
  rm -f "$BACKUP_FILE"
  log "備份檔壓縮損毀，已刪除" >&2
  exit 1
fi

if ! zcat "$BACKUP_FILE" 2>/dev/null | grep -q "PostgreSQL database dump complete"; then
  rm -f "$BACKUP_FILE"
  log "備份檔缺少結尾標記（內容不完整或為空），已刪除" >&2
  exit 1
fi

SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
log "備份完成：${BACKUP_FILE}（${SIZE}）"

# ------------------------------------------------------------
# 同步一份到 Windows 桌面（異地保存）
# 失敗只警告不中斷 —— 電腦睡眠/喚醒後 /mnt/c 掛載會失效，這是已知環境問題
# ------------------------------------------------------------
if [[ ! -d "$WIN_DESKTOP" ]]; then
  log "/mnt/c 未掛載，跳過 Windows 同步。若電腦曾睡眠/喚醒，請在 Windows PowerShell 執行 wsl --shutdown" >&2
elif ! mkdir -p "$WIN_MIRROR_DIR" 2>/dev/null; then
  log "無法建立 ${WIN_MIRROR_DIR}，跳過 Windows 同步" >&2
elif cp "$BACKUP_FILE" "$WIN_MIRROR_DIR/" 2>/dev/null; then
  log "已同步到 Windows 桌面：${WIN_MIRROR_DIR}/$(basename "$BACKUP_FILE")"
else
  log "Windows 同步失敗（/mnt/c I/O error？）" >&2
fi

# ------------------------------------------------------------
# 清理本機舊備份（Windows 端刻意不清，當作異地長期封存）
# ------------------------------------------------------------
# 失敗殘留的空/損毀檔（0 bytes 與 gzip 空檔約 20-30 bytes）
# 注意：必須用 -size -1024c（byte 單位）。-size -1k 是以 1k 區塊計算且向上取整，
# 20 bytes 的檔案算作 1 個區塊，永遠不符合「小於 1 個區塊」，會漏刪。
find "$BACKUP_DIR" -maxdepth 1 -name "*.sql.gz" -size -1024c -delete 2>/dev/null || true

# 超過 KEEP_DAYS 天的備份 —— 排程備份與 edit hook 產生的 pre_edit_* 都要清
# （舊版只清 ${DB_NAME}_*，pre_edit_* 從不清理，是本機堆積到 1.7GB 的原因）
find "$BACKUP_DIR" -maxdepth 1 -name "${DB_NAME}_*.sql.gz" -mtime "+${KEEP_DAYS}" -delete 2>/dev/null || true
find "$BACKUP_DIR" -maxdepth 1 -name "pre_edit_*.sql.gz"   -mtime "+${KEEP_DAYS}" -delete 2>/dev/null || true

REMAINING=$(find "$BACKUP_DIR" -maxdepth 1 -name "*.sql.gz" | wc -l)
LOCAL_SIZE=$(du -sh "$BACKUP_DIR" | cut -f1)
log "本機保留 ${REMAINING} 份備份（${LOCAL_SIZE}，超過 ${KEEP_DAYS} 天自動刪除）"
