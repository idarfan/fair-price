#!/usr/bin/env bash
#
# 讓 pm2 daemon 以 TZ=UTC 執行。
#
# ── 問題 ──────────────────────────────────────────────────────────────
# pm2 的 cron_restart 是由 daemon 自己解讀的，用的是 **daemon 的時區**。
# /etc/systemd/system/pm2-idarfan.service 只設了 PATH 與 PM2_HOME，沒有 TZ，
# 所以 daemon 沿用 /etc/localtime（Asia/Taipei），而 bin/iv-*.sh 的註解
# 明確假設「pm2 daemon 必須以 TZ=UTC 啟動」。
#
# 結果是 fairprice 的三個排程全部早 8 小時：
#
#   iv-skew-intraday   */30 13-20 * * 1-5  應 ET 09:00-16:00 → 實 ET 01:00-08:00
#   iv-daily-snapshot  30 20 * * 1-5       應 ET 16:30       → 實 ET 08:30
#   iv-skew-snapshot   45 20 * * 1-5       應 ET 16:45       → 實 ET 08:45
#
# intraday 因此每次都判定「非交易時段」而跳過——skew_rank_intradays 從
# 2026-05-19 起就沒有新資料；另外兩個抓到的是前一日收盤而非當日。
#
# ── 做法 ──────────────────────────────────────────────────────────────
# 用 systemd drop-in（附加式、可逆、不會被套件更新蓋掉）加上 Environment=TZ=UTC，
# 然後重啟 pm2-idarfan.service（ExecStop=pm2 kill / ExecStart=pm2 resurrect）。
#
# ── 注意 ──────────────────────────────────────────────────────────────
# * 會重啟 **全部** pm2 process（不只 fairprice）。
# * resurrect 會讓 5 個 cron job 各跑一次：兩個 DB 備份（多一份，無害）、
#   三個 iv-*（非交易日會乾淨跳過）。**建議在美股休市時段執行。**
#
# 用法：
#   ./scripts/fix-pm2-timezone.sh              套用
#   ./scripts/fix-pm2-timezone.sh --rollback   還原
#   ./scripts/fix-pm2-timezone.sh --check      只檢查現況，不做任何改動

set -euo pipefail

UNIT="pm2-idarfan"
DROPIN_DIR="/etc/systemd/system/${UNIT}.service.d"
DROPIN="${DROPIN_DIR}/timezone.conf"
BACKUP_DIR="${HOME}/.pm2/tz-fix-backup"

c_ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; }
c_bad()  { printf '  \033[31m✗\033[0m %s\n' "$*"; }
c_warn() { printf '  \033[33m!\033[0m %s\n' "$*"; }
head_()  { printf '\n\033[1m── %s ─────────────────────────\033[0m\n' "$*"; }

daemon_tz() {
  local pid
  pid="$(pgrep -f 'PM2 v' | head -1 || true)"
  [ -z "$pid" ] && { echo "(daemon 未執行)"; return; }
  tr '\0' '\n' < "/proc/${pid}/environ" 2>/dev/null \
    | awk -F= '/^TZ=/{print $2; found=1} END{if(!found) print "(未設定 → /etc/localtime = " ENVIRON["LOCALTIME"] ")"}'
}

show_state() {
  head_ "現況"
  echo "  /etc/localtime      → $(readlink -f /etc/localtime)"
  echo "  pm2 daemon 的 TZ    → $(LOCALTIME="$(readlink -f /etc/localtime | xargs basename)" daemon_tz)"
  if [ -f "$DROPIN" ]; then c_ok "drop-in 已存在：$DROPIN"; else c_warn "drop-in 尚未建立"; fi
  echo
  echo "  pm2 process："
  pm2 jlist 2>/dev/null | python3 -c "
import sys, json
d = json.load(sys.stdin)
on = sum(1 for p in d if p['pm2_env']['status'] == 'online')
print(f'    共 {len(d)} 個，online {on} 個')
for p in sorted(d, key=lambda x: x['name']):
    cr = p['pm2_env'].get('cron_restart')
    if cr: print(f\"    {p['name']:24} cron: {cr}\")
" || c_bad "pm2 沒有回應"
}

case "${1:-}" in
  --check)
    show_state
    echo
    echo "  （只檢查，未做任何改動）"
    exit 0
    ;;

  --rollback)
    head_ "還原"
    if [ ! -f "$DROPIN" ]; then
      c_warn "drop-in 不存在，無需還原"
      exit 0
    fi
    sudo rm -rf "$DROPIN_DIR"
    sudo systemctl daemon-reload
    sudo systemctl restart "$UNIT"
    c_ok "已移除 drop-in 並重啟 $UNIT"
    sleep 5
    show_state
    exit 0
    ;;

  "")
    ;;

  *)
    echo "未知參數：$1"
    echo "用法：$0 [--check | --rollback]"
    exit 2
    ;;
esac

# ─────────────────────────────────────────────────────────────────────
# 前置檢查
# ─────────────────────────────────────────────────────────────────────
head_ "前置檢查"

[ -f "/etc/systemd/system/${UNIT}.service" ] \
  || { c_bad "找不到 /etc/systemd/system/${UNIT}.service"; exit 1; }
c_ok "unit 檔存在"

systemctl is-active --quiet "$UNIT" \
  || { c_bad "$UNIT 不是 active，先確認 pm2 是由它管理"; exit 1; }
c_ok "$UNIT 是 active"

command -v pm2 >/dev/null || { c_bad "找不到 pm2"; exit 1; }
pm2 ping >/dev/null 2>&1 || { c_bad "pm2 daemon 沒有回應"; exit 1; }
c_ok "pm2 daemon 有回應"

if [ -f "$DROPIN" ]; then
  c_warn "drop-in 已經存在，重跑會覆蓋它（內容相同則等同無操作）"
fi

# ─────────────────────────────────────────────────────────────────────
# 備份：把當前 process 清單存進 dump，並另存一份供比對
# ─────────────────────────────────────────────────────────────────────
head_ "備份"

mkdir -p "$BACKUP_DIR"
STAMP="$(date -u '+%Y%m%d_%H%M%S')"

pm2 save >/dev/null 2>&1 || { c_bad "pm2 save 失敗，中止（沒有可靠的 dump 就不該 kill）"; exit 1; }
cp "${HOME}/.pm2/dump.pm2" "${BACKUP_DIR}/dump.pm2.${STAMP}"
c_ok "dump 已更新並備份 → ${BACKUP_DIR}/dump.pm2.${STAMP}"

BEFORE="${BACKUP_DIR}/state_before.${STAMP}.txt"
pm2 jlist 2>/dev/null | python3 -c "
import sys, json
d = json.load(sys.stdin)
for p in sorted(d, key=lambda x: x['name']):
    print(f\"{p['name']}\t{p['pm2_env']['status']}\")
" > "$BEFORE"
BEFORE_COUNT="$(wc -l < "$BEFORE")"
c_ok "已記錄 ${BEFORE_COUNT} 個 process 的狀態 → $BEFORE"

[ "$BEFORE_COUNT" -gt 0 ] || { c_bad "process 數為 0，狀態不對，中止"; exit 1; }

# ─────────────────────────────────────────────────────────────────────
# 套用
# ─────────────────────────────────────────────────────────────────────
head_ "套用 TZ=UTC"

echo "  接下來需要 sudo（建立 drop-in、daemon-reload、重啟 pm2）"
sudo bash -s <<SUDO_SCRIPT
set -euo pipefail
mkdir -p "$DROPIN_DIR"
cat > "$DROPIN" <<'CONF'
# pm2 的 cron_restart 由 daemon 解讀，用的是 daemon 自己的時區。
# 未設定 TZ 時會沿用 /etc/localtime（Asia/Taipei），使 fairprice 的
# iv-* 排程全部早 8 小時——bin/iv-*.sh 的註解假設 daemon 是 UTC。
#
# 由 scripts/fix-pm2-timezone.sh 建立；還原用同一支腳本的 --rollback。
[Service]
Environment=TZ=UTC
CONF
systemctl daemon-reload
systemctl restart "$UNIT"
SUDO_SCRIPT

c_ok "drop-in 已建立、$UNIT 已重啟"

# ─────────────────────────────────────────────────────────────────────
# 驗證
# ─────────────────────────────────────────────────────────────────────
head_ "等待 process 回復"

for i in $(seq 1 20); do
  sleep 2
  if pm2 ping >/dev/null 2>&1; then
    NOW="$(pm2 jlist 2>/dev/null | python3 -c 'import sys,json; print(len(json.load(sys.stdin)))' || echo 0)"
    printf '  第 %2d 次：%s 個 process\n' "$i" "$NOW"
    [ "$NOW" -ge "$BEFORE_COUNT" ] && break
  else
    printf '  第 %2d 次：daemon 尚未就緒\n' "$i"
  fi
done

head_ "驗證"

TZ_NOW="$(daemon_tz)"
if [ "$TZ_NOW" = "UTC" ]; then
  c_ok "daemon TZ = UTC"
else
  c_bad "daemon TZ = ${TZ_NOW}（預期 UTC）——請檢查 drop-in 是否生效"
fi

AFTER="${BACKUP_DIR}/state_after.${STAMP}.txt"
pm2 jlist 2>/dev/null | python3 -c "
import sys, json
d = json.load(sys.stdin)
for p in sorted(d, key=lambda x: x['name']):
    print(f\"{p['name']}\t{p['pm2_env']['status']}\")
" > "$AFTER"

MISSING="$(comm -23 <(cut -f1 "$BEFORE" | sort) <(cut -f1 "$AFTER" | sort) || true)"
if [ -z "$MISSING" ]; then
  c_ok "全部 ${BEFORE_COUNT} 個 process 都回來了"
else
  c_bad "以下 process 沒有回來："
  echo "$MISSING" | sed 's/^/      /'
  echo "      還原：$0 --rollback"
fi

echo
echo "  排程的下次觸發時刻（UTC / 美東）："
pm2 jlist 2>/dev/null | python3 -c "
import sys, json, datetime, zoneinfo
d = json.load(sys.stdin)
et = zoneinfo.ZoneInfo('America/New_York')
for p in sorted(d, key=lambda x: x['name']):
    cr = p['pm2_env'].get('cron_restart')
    if not cr: continue
    print(f\"    {p['name']:24} {cr}\")
"
echo
echo "  提醒：13-20 UTC = ET 09:00-16:00（夏令），冬令會變 ET 08:00-15:00。"
echo "        這個位移原本就存在，不是這次改動造成的。"
echo
echo "  備份位置：$BACKUP_DIR"
echo "  還原指令：$0 --rollback"
