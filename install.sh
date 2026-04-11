#!/usr/bin/env bash
# ============================================================
#  FairPrice — WSL2 互動式安裝程式
#  用法：cd fairprice-bundle && bash install.sh
#  需要：WSL2 Ubuntu 22.04+，sudo 權限，網路連線
# ============================================================
set -euo pipefail

# ── 版本常數 ────────────────────────────────────────────────
readonly SCRIPT_VERSION="1.0.0"
readonly RUBY_VERSION="4.0.1"
readonly BUNDLER_VERSION="4.0.7"
readonly MIN_NODE_MAJOR=20
readonly RAILS_PORT=3003
readonly VITE_PORT=3036

# ── 顏色 ────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ── 輸出工具 ────────────────────────────────────────────────
info()    { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok()      { echo -e "${GREEN}[ OK ]${NC}  $*"; }
skip()    { echo -e "        ${CYAN}[SKIP]${NC} $* （已完成）"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[FAIL]${NC}  $*" >&2; }
step()    { echo -e "\n${BOLD}${BLUE}━━━ $* ━━━${NC}"; }
hr()      { echo -e "${BLUE}────────────────────────────────────────${NC}"; }

ask() {
  # ask VAR_NAME "提示文字" [預設值]
  local var="$1" msg="$2" default="${3:-}"
  local input
  if [[ -n "$default" ]]; then
    echo -en "${YELLOW}[?]${NC} ${msg} [${default}]: "
  else
    echo -en "${YELLOW}[?]${NC} ${msg}: "
  fi
  read -r input
  printf -v "$var" '%s' "${input:-$default}"
}

ask_secret() {
  # ask_secret VAR_NAME "提示文字"
  local var="$1" msg="$2"
  echo -en "${YELLOW}[?]${NC} ${msg}: "
  local input
  read -rs input
  echo
  printf -v "$var" '%s' "$input"
}

ask_yn() {
  # ask_yn "提示" → 回傳 0=yes, 1=no
  local msg="$1" default="${2:-n}"
  local prompt_hint
  [[ "$default" == "y" ]] && prompt_hint="Y/n" || prompt_hint="y/N"
  echo -en "${YELLOW}[?]${NC} ${msg} (${prompt_hint}): "
  local input
  read -r input
  input="${input:-$default}"
  [[ "${input,,}" == "y" ]]
}

# ── 全局變數（由互動輸入填入）──────────────────────────────
INSTALL_USER=""
HOME_DIR=""
APP_DIR=""
HAS_SYSTEMD=false
FINNHUB_API_KEY=""
GROQ_API_KEY=""
TELEGRAM_BOT_TOKEN=""
TELEGRAM_CHAT_ID=""
OUOU_TELEGRAM_CHAT_ID=""
DB_HOST="localhost"
DB_PORT="5432"
DB_USER=""
DB_PASSWORD=""

# ============================================================
# PHASE 0：環境確認
# ============================================================
phase0_preflight() {
  step "環境確認"

  # 修復從隨身碟複製後可能遺失的執行權限
  find "$(pwd)" -name "*.sh" -exec chmod +x {} \; 2>/dev/null || true

  # 確認在 WSL2
  if ! grep -qi "microsoft" /proc/version 2>/dev/null; then
    warn "未偵測到 WSL2 環境，繼續安裝可能遇到問題"
    ask_yn "確定繼續？" "n" || { info "安裝中止"; exit 0; }
  else
    ok "WSL2 環境確認"
  fi

  # 偵測 systemd
  if [[ "$(cat /proc/1/comm 2>/dev/null)" == "systemd" ]]; then
    HAS_SYSTEMD=true
    ok "systemd 可用"
  else
    warn "systemd 未啟用（建議在 /etc/wsl.conf 加入 [boot] systemd=true 後重啟 WSL）"
  fi

  # 確認在 app 目錄
  if [[ ! -f "Gemfile" ]]; then
    error "找不到 Gemfile！請在 fairprice-bundle 目錄內執行此腳本"
    error "用法：cd fairprice-bundle && bash install.sh"
    exit 1
  fi

  # 確認 sudo 可用
  if ! sudo -v 2>/dev/null; then
    error "此安裝程式需要 sudo 權限，請確認使用者在 sudoers 中"
    exit 1
  fi

  INSTALL_USER="$USER"
  HOME_DIR="$HOME"
  APP_DIR="$(pwd)"

  hr
  echo -e "  安裝使用者：${BOLD}${INSTALL_USER}${NC}"
  echo -e "  Home 目錄：${BOLD}${HOME_DIR}${NC}"
  echo -e "  App 目錄：${BOLD}${APP_DIR}${NC}"
  echo -e "  systemd：$(${HAS_SYSTEMD} && echo '可用' || echo '不可用')"
  hr
}

# ============================================================
# PHASE 1：系統套件
# ============================================================
phase1_system_deps() {
  step "系統套件安裝"
  info "更新套件清單..."
  sudo apt-get update -q

  local pkgs=(
    git curl wget build-essential
    libssl-dev libreadline-dev zlib1g-dev libyaml-dev
    libffi-dev libgdbm-dev libgmp-dev libpq-dev
    postgresql postgresql-contrib
  )

  local missing=()
  for pkg in "${pkgs[@]}"; do
    dpkg -l "$pkg" &>/dev/null || missing+=("$pkg")
  done

  if [[ ${#missing[@]} -eq 0 ]]; then
    skip "所有系統套件已安裝"
  else
    info "安裝缺少的套件：${missing[*]}"
    sudo apt-get install -y "${missing[@]}"
    ok "系統套件安裝完成"
  fi
}

# ============================================================
# PHASE 2：rbenv + Ruby 4.0.1
# ============================================================
phase2_ruby() {
  step "rbenv + Ruby ${RUBY_VERSION}"

  # rbenv
  if [[ -d "${HOME_DIR}/.rbenv" ]]; then
    info "更新 rbenv..."
    git -C "${HOME_DIR}/.rbenv" pull --quiet
  else
    info "安裝 rbenv..."
    git clone https://github.com/rbenv/rbenv.git "${HOME_DIR}/.rbenv" --quiet
    ok "rbenv 安裝完成"
  fi

  # ruby-build plugin
  local plugin_dir="${HOME_DIR}/.rbenv/plugins/ruby-build"
  if [[ -d "$plugin_dir" ]]; then
    info "更新 ruby-build..."
    git -C "$plugin_dir" pull --quiet
  else
    info "安裝 ruby-build..."
    git clone https://github.com/rbenv/ruby-build.git "$plugin_dir" --quiet
  fi
  ok "ruby-build 更新完成"

  # PATH（只加一次）
  if ! grep -q 'rbenv init' "${HOME_DIR}/.bashrc" 2>/dev/null; then
    cat >> "${HOME_DIR}/.bashrc" << 'BASHRC'

# rbenv（由 fairprice install.sh 加入）
export PATH="$HOME/.rbenv/bin:$HOME/.rbenv/shims:$PATH"
eval "$(~/.rbenv/bin/rbenv init - --no-rehash bash)"
BASHRC
    ok "rbenv PATH 加入 .bashrc"
  fi

  # 啟用 rbenv（當前 session）
  export PATH="${HOME_DIR}/.rbenv/bin:${HOME_DIR}/.rbenv/shims:$PATH"
  eval "$("${HOME_DIR}/.rbenv/bin/rbenv" init - --no-rehash bash)"

  # Ruby 4.0.1
  if rbenv versions 2>/dev/null | grep -q "${RUBY_VERSION}"; then
    skip "Ruby ${RUBY_VERSION} 已安裝"
  else
    warn "即將編譯 Ruby ${RUBY_VERSION}，約需 10–20 分鐘，請耐心等待..."
    RUBY_CONFIGURE_OPTS="--enable-shared" rbenv install "${RUBY_VERSION}" 2>&1 | \
      while IFS= read -r line; do echo "    $line"; done
    ok "Ruby ${RUBY_VERSION} 安裝完成"
  fi

  rbenv global "${RUBY_VERSION}"
  rbenv rehash

  # bundler
  if gem list bundler | grep -q "${BUNDLER_VERSION}"; then
    skip "bundler ${BUNDLER_VERSION} 已安裝"
  else
    gem install bundler -v "${BUNDLER_VERSION}" --no-document
    ok "bundler ${BUNDLER_VERSION} 安裝完成"
  fi
}

# ============================================================
# PHASE 3：Node.js + pm2
# ============================================================
phase3_nodejs() {
  step "Node.js + pm2"

  # Node.js
  if command -v node &>/dev/null; then
    local node_major
    node_major=$(node -e "process.stdout.write(String(parseInt(process.version.slice(1))))")
    if [[ "$node_major" -ge "$MIN_NODE_MAJOR" ]]; then
      skip "Node.js $(node --version) 已符合需求（>= v${MIN_NODE_MAJOR}）"
    else
      warn "Node.js $(node --version) 版本過舊，需要 v${MIN_NODE_MAJOR}+，重新安裝..."
      _install_nodejs
    fi
  else
    _install_nodejs
  fi

  # npm global prefix（避免 sudo npm install -g）
  if ! npm config get prefix 2>/dev/null | grep -q "npm-global"; then
    mkdir -p "${HOME_DIR}/.npm-global"
    npm config set prefix "${HOME_DIR}/.npm-global"
    if ! grep -q 'npm-global' "${HOME_DIR}/.bashrc" 2>/dev/null; then
      echo -e '\n# npm global（由 fairprice install.sh 加入）\nexport PATH="$HOME/.npm-global/bin:$PATH"' >> "${HOME_DIR}/.bashrc"
    fi
    ok "npm global prefix 設定完成"
  fi
  export PATH="${HOME_DIR}/.npm-global/bin:$PATH"

  # pm2
  if command -v pm2 &>/dev/null; then
    skip "pm2 $(pm2 --version 2>/dev/null | head -1) 已安裝"
  else
    npm install -g pm2
    ok "pm2 安裝完成"
  fi
}

_install_nodejs() {
  info "安裝 Node.js LTS（透過 NodeSource）..."
  curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash - &>/dev/null
  sudo apt-get install -y nodejs &>/dev/null
  ok "Node.js $(node --version) 安裝完成"
}

# ============================================================
# PHASE 4：互動式 API Key 收集 → .env
# ============================================================

# 從 .env 讀取單一欄位值
_env_get() {
  local key="$1"
  grep "^${key}=" .env 2>/dev/null | cut -d= -f2- || echo ""
}

# 顯示目前狀態標籤
_env_status() {
  local val="$1"
  if [[ -n "$val" ]]; then
    echo -e "${GREEN}已設定${NC}"
  else
    echo -e "${YELLOW}未填${NC}"
  fi
}

# 詢問一個 secret 欄位，保留現有值或輸入新值
# ask_secret_update VAR "標籤" "目前值" "是否必填(required/optional)"
ask_secret_update() {
  local var="$1" label="$2" current="$3" required="${4:-optional}"
  local status hint input

  if [[ -n "$current" ]]; then
    status="${GREEN}已設定${NC}"
    hint="Enter 保留，或輸入新值覆蓋"
  else
    status="${YELLOW}未填${NC}"
    [[ "$required" == "required" ]] && hint="必填，請輸入" || hint="選填，Enter 跳過"
  fi

  echo -en "${YELLOW}[?]${NC} ${label} [${status}，${hint}]: "
  read -rs input
  echo

  if [[ -n "$input" ]]; then
    printf -v "$var" '%s' "$input"
  else
    printf -v "$var" '%s' "$current"
  fi
}

# 詢問一個普通欄位，保留現有值或輸入新值
ask_update() {
  local var="$1" label="$2" current="$3"
  local status

  [[ -n "$current" ]] && status="${GREEN}${current}${NC}" || status="${YELLOW}未填${NC}"
  echo -en "${YELLOW}[?]${NC} ${label} [${status}]: "
  local input
  read -r input

  if [[ -n "$input" ]]; then
    printf -v "$var" '%s' "$input"
  else
    printf -v "$var" '%s' "$current"
  fi
}

phase4_env() {
  step "API Keys 設定"

  echo ""
  hr
  echo -e "  申請連結（皆免費，無需信用卡）："
  echo -e "  ${CYAN}FINNHUB_API_KEY${NC} → https://finnhub.io"
  echo -e "  ${CYAN}GROQ_API_KEY${NC}    → https://console.groq.com"
  hr
  echo ""

  # ── 讀取現有值（首次安裝全為空）────────────────────────
  local cur_finnhub cur_groq cur_tg_token cur_tg_chat cur_ouou_chat
  local cur_db_host cur_db_port cur_db_user cur_db_pass
  if [[ -f ".env" ]]; then
    cur_finnhub=$(_env_get "FINNHUB_API_KEY")
    cur_groq=$(_env_get "GROQ_API_KEY")
    cur_tg_token=$(_env_get "TELEGRAM_BOT_TOKEN")
    cur_tg_chat=$(_env_get "TELEGRAM_CHAT_ID")
    cur_ouou_chat=$(_env_get "OUOU_TELEGRAM_CHAT_ID")
    cur_db_host=$(_env_get "DB_HOST")
    cur_db_port=$(_env_get "DB_PORT")
    cur_db_user=$(_env_get "DB_USER")
    cur_db_pass=$(_env_get "DB_PASSWORD")
    info ".env 已存在，逐項確認（Enter 保留現有值）"
  else
    cur_db_host="localhost"
    cur_db_port="5432"
    cur_db_user="${INSTALL_USER}"
    info "首次設定，請依提示填入各項目"
  fi
  echo ""

  # ── 必填 ────────────────────────────────────────────────
  echo -e "  ${BOLD}【必填】核心功能 API Keys${NC}"

  ask_secret_update FINNHUB_API_KEY "FINNHUB_API_KEY" "$cur_finnhub" "required"
  while [[ -z "$FINNHUB_API_KEY" ]]; do
    warn "FINNHUB_API_KEY 為必填，請輸入（至 https://finnhub.io 申請）"
    ask_secret_update FINNHUB_API_KEY "FINNHUB_API_KEY" "" "required"
  done

  ask_secret_update GROQ_API_KEY "GROQ_API_KEY" "$cur_groq" "required"
  while [[ -z "$GROQ_API_KEY" ]]; do
    warn "GROQ_API_KEY 為必填，請輸入（至 https://console.groq.com 申請）"
    ask_secret_update GROQ_API_KEY "GROQ_API_KEY" "" "required"
  done

  # ── 選填 ────────────────────────────────────────────────
  echo ""
  echo -e "  ${BOLD}【選填】Telegram 推播功能${NC}（未填則停用，日後可重跑安裝程式補填）"

  ask_secret_update TELEGRAM_BOT_TOKEN  "TELEGRAM_BOT_TOKEN"     "$cur_tg_token"  "optional"
  ask_secret_update TELEGRAM_CHAT_ID    "TELEGRAM_CHAT_ID"       "$cur_tg_chat"   "optional"
  ask_secret_update OUOU_TELEGRAM_CHAT_ID "OUOU_TELEGRAM_CHAT_ID" "$cur_ouou_chat" "optional"

  # ── 資料庫 ───────────────────────────────────────────────
  echo ""
  echo -e "  ${BOLD}【資料庫】${NC}（保留預設值即可）"

  ask_update DB_HOST     "DB_HOST"     "${cur_db_host:-localhost}"
  ask_update DB_PORT     "DB_PORT"     "${cur_db_port:-5432}"
  ask_update DB_USER     "DB_USER"     "${cur_db_user:-$INSTALL_USER}"
  ask_secret_update DB_PASSWORD "DB_PASSWORD（可留空）" "${cur_db_pass:-}" "optional"

  # ── 寫入 .env ────────────────────────────────────────────
  cat > .env << EOF
# FairPrice 環境變數（由 install.sh 更新於 $(date '+%Y-%m-%d %H:%M:%S')）
# ⚠️  請勿提交此檔案至 git

# API Keys（必填）
FINNHUB_API_KEY=${FINNHUB_API_KEY}
GROQ_API_KEY=${GROQ_API_KEY}

# Telegram Bot（選填，未填則停用 Bot 與盤前報告功能）
TELEGRAM_BOT_TOKEN=${TELEGRAM_BOT_TOKEN:-}
TELEGRAM_CHAT_ID=${TELEGRAM_CHAT_ID:-}
OUOU_TELEGRAM_CHAT_ID=${OUOU_TELEGRAM_CHAT_ID:-}

# 資料庫
DB_HOST=${DB_HOST}
DB_PORT=${DB_PORT}
DB_USER=${DB_USER}
DB_PASSWORD=${DB_PASSWORD:-}

# Rails
RAILS_ENV=development
EOF

  chmod 600 .env

  # 顯示最終狀態摘要
  echo ""
  echo -e "  ${BOLD}設定完成摘要：${NC}"
  echo -e "  FINNHUB_API_KEY       $(_env_status "$FINNHUB_API_KEY")"
  echo -e "  GROQ_API_KEY          $(_env_status "$GROQ_API_KEY")"
  echo -e "  TELEGRAM_BOT_TOKEN    $(_env_status "${TELEGRAM_BOT_TOKEN:-}")"
  echo -e "  TELEGRAM_CHAT_ID      $(_env_status "${TELEGRAM_CHAT_ID:-}")"
  echo -e "  OUOU_TELEGRAM_CHAT_ID $(_env_status "${OUOU_TELEGRAM_CHAT_ID:-}")"
  echo ""
  ok ".env 更新完成"
}

# ============================================================
# PHASE 5：master.key 處理
# ============================================================
phase5_master_key() {
  step "Rails credentials 處理"

  if [[ -f "config/master.key" ]]; then
    skip "config/master.key 已存在"
    return 0
  fi

  warn "config/master.key 不存在（新機器正常現象）"
  echo ""
  echo -e "  如果你有${BOLD}舊機器的 master.key${NC}，請貼上其 32 字元 hex 內容："
  echo -e "  （此 app 不使用 encrypted credentials，可以安全重新生成，直接按 Enter 即可）"
  echo -en "${YELLOW}[?]${NC} master.key 內容（留空則自動重新生成）: "
  read -r MASTER_KEY_INPUT

  if [[ -n "$MASTER_KEY_INPUT" ]]; then
    echo "$MASTER_KEY_INPUT" > config/master.key
    chmod 600 config/master.key
    ok "master.key 從輸入還原"
  else
    info "重新生成 Rails credentials..."
    rm -f config/credentials.yml.enc
    EDITOR=true bundle exec rails credentials:edit &>/dev/null || true
    ok "新 credentials 生成完成"
  fi
}

# ============================================================
# PHASE 6：bundle install + npm install
# ============================================================
phase6_deps() {
  step "安裝依賴套件"

  info "執行 bundle install..."
  bundle install 2>&1 | tail -5
  ok "bundle install 完成"

  info "執行 npm install..."
  npm install --silent
  ok "npm install 完成"
}

# ============================================================
# PHASE 7：PostgreSQL 設定 + 資料庫建立
# ============================================================
phase7_database() {
  step "資料庫設定"

  # 啟動 PostgreSQL
  if $HAS_SYSTEMD; then
    sudo systemctl start postgresql &>/dev/null || true
  else
    sudo service postgresql start &>/dev/null || true
  fi
  ok "PostgreSQL 服務已啟動"

  # 確保 localhost TCP 連線允許 md5 或 scram-sha-256
  _configure_pg_hba

  # 取得 PostgreSQL 版本
  local pg_ver
  pg_ver=$(psql --version 2>/dev/null | grep -oP '\d+' | head -1 || echo "")

  # 建立 DB user（若不存在）
  local user_exists
  user_exists=$(sudo -u postgres psql -tAc \
    "SELECT 1 FROM pg_roles WHERE rolname='${DB_USER}'" 2>/dev/null || echo "")

  if [[ "$user_exists" != "1" ]]; then
    info "建立 PostgreSQL 使用者 '${DB_USER}'..."
    if [[ -n "${DB_PASSWORD:-}" ]]; then
      sudo -u postgres psql -c \
        "CREATE USER \"${DB_USER}\" WITH PASSWORD '${DB_PASSWORD}' CREATEDB;" &>/dev/null
    else
      sudo -u postgres createuser --createdb "${DB_USER}" 2>/dev/null || true
    fi
    ok "PostgreSQL 使用者 '${DB_USER}' 建立完成"
  else
    skip "PostgreSQL 使用者 '${DB_USER}' 已存在"
  fi

  # 載入 .env 供 rails 指令使用
  set -a; source .env; set +a

  info "建立資料庫並執行 migrate..."
  bundle exec rails db:create 2>/dev/null || info "資料庫已存在，略過建立"
  bundle exec rails db:migrate
  ok "資料庫 migrate 完成"
}

_configure_pg_hba() {
  local pg_ver
  pg_ver=$(psql --version 2>/dev/null | grep -oP '\d+' | head -1 || echo "")
  [[ -z "$pg_ver" ]] && return

  local hba_file="/etc/postgresql/${pg_ver}/main/pg_hba.conf"
  [[ ! -f "$hba_file" ]] && return

  if grep -qP '^host\s+all\s+all\s+127\.0\.0\.1' "$hba_file" 2>/dev/null; then
    skip "pg_hba.conf TCP 認證已設定"
    return
  fi

  info "設定 PostgreSQL TCP 認證（md5）..."
  sudo sed -i \
    '/^# IPv4 local connections:/a host    all             all             127.0.0.1\/32            md5' \
    "$hba_file" 2>/dev/null || true

  if $HAS_SYSTEMD; then
    sudo systemctl reload postgresql &>/dev/null || true
  else
    sudo service postgresql reload &>/dev/null || true
  fi
  ok "pg_hba.conf 設定完成"
}

# ============================================================
# PHASE 8：覆寫硬寫路徑的設定檔
# ============================================================
phase8_fix_paths() {
  step "更新設定檔路徑"

  local rbenv_root="${HOME_DIR}/.rbenv"
  local npm_global_bin="${HOME_DIR}/.npm-global/bin"
  local node_bin_dir
  node_bin_dir="$(dirname "$(which node)" 2>/dev/null || echo "/usr/bin")"
  local full_path="${rbenv_root}/shims:${rbenv_root}/bin:${npm_global_bin}:${node_bin_dir}:/usr/local/bin:/usr/bin:/bin"

  # 是否啟用 Telegram Bot
  local telegram_apps=""
  if [[ -n "${TELEGRAM_BOT_TOKEN:-}" ]]; then
    telegram_apps=$(cat << TELEGRAM_BLOCK

    // ── 歐歐 Telegram Bot
    {
      name: 'ouou-telegram-bot',
      script: 'bin/rails',
      args: 'runner "TelegramBotPollingService.new.run"',
      cwd: '${APP_DIR}',
      interpreter: 'none',
      env: {
        RAILS_ENV: 'development',
        HOME: '${HOME_DIR}',
        PATH: '${full_path}',
        RBENV_ROOT: '${rbenv_root}',
      },
      autorestart: true,
      watch: false,
      max_restarts: 10,
      min_uptime: '10s',
      restart_delay: 5000,
    },
TELEGRAM_BLOCK
)
  fi

  # ── ecosystem.config.cjs ─────────────────────────────────
  cat > ecosystem.config.cjs << ECOSYSTEM
module.exports = {
  apps: [
    // ── Rails（Puma on :${RAILS_PORT}）
    {
      name: 'fairprice-rails',
      script: './bin/start-rails.sh',
      cwd: '${APP_DIR}',
      interpreter: '/bin/bash',
      env: {
        RAILS_ENV: 'development',
        HOME: '${HOME_DIR}',
        PATH: '${full_path}',
        RBENV_ROOT: '${rbenv_root}',
      },
      autorestart: true,
      watch: false,
      max_restarts: 5,
      min_uptime: '10s',
      restart_delay: 5000,
    },

    // ── Vite dev server（:${VITE_PORT}）
    {
      name: 'fairprice-vite',
      script: 'npm',
      args: 'exec vite -- --mode development',
      cwd: '${APP_DIR}',
      interpreter: 'none',
      autorestart: true,
      watch: false,
      max_restarts: 5,
      restart_delay: 3000,
    },
${telegram_apps}
    // ── 歐歐每日盤前報告（週一至五 13:00 UTC）
    {
      name: 'ouou-pre-market',
      script: './bin/ouou-pre-market.sh',
      cwd: '${APP_DIR}',
      interpreter: '/bin/bash',
      env: {
        RAILS_ENV: 'development',
        HOME: '${HOME_DIR}',
        PATH: '${full_path}',
        RBENV_ROOT: '${rbenv_root}',
      },
      cron_restart: '0 13 * * 1-5',
      autorestart: false,
      watch: false,
    },
  ],
}
ECOSYSTEM
  ok "ecosystem.config.cjs 更新完成"

  # ── bin/start-rails.sh ──────────────────────────────────
  cat > bin/start-rails.sh << RAILS_SCRIPT
#!/bin/bash
set -e

APP_DIR="${APP_DIR}"
PID_FILE="\$APP_DIR/tmp/pids/server.pid"
HEALTH_URL="http://localhost:${RAILS_PORT}/up"
MAX_WAIT=30

# 載入 .env
if [ -f "\$APP_DIR/.env" ]; then
  set -a; source "\$APP_DIR/.env"; set +a
fi

# 清除 stale pid
rm -f "\$PID_FILE"

# 啟動 Rails（前景，讓 pm2 追蹤）
bundle exec rails server -p ${RAILS_PORT} -b 0.0.0.0 &
RAILS_PID=\$!

echo "[start-rails] Waiting for Rails to be ready..."
for i in \$(seq 1 \$MAX_WAIT); do
  sleep 1
  if curl -sf "\$HEALTH_URL" > /dev/null 2>&1; then
    echo "[start-rails] Rails is up (\${i}s)"
    wait \$RAILS_PID
    exit \$?
  fi
done

echo "[start-rails] ERROR: Rails did not respond within \${MAX_WAIT}s"
kill "\$RAILS_PID" 2>/dev/null
exit 1
RAILS_SCRIPT
  chmod +x bin/start-rails.sh
  ok "bin/start-rails.sh 更新完成"

  # ── bin/ouou-pre-market.sh ──────────────────────────────
  cat > bin/ouou-pre-market.sh << PRE_MARKET
#!/bin/bash
# 歐歐每日盤前報告
# 由 pm2 cron 每週一至五 13:00 UTC 自動執行

set -e

export HOME="${HOME_DIR}"
export RBENV_ROOT="\$HOME/.rbenv"
export PATH="\$RBENV_ROOT/shims:\$RBENV_ROOT/bin:/usr/bin:/bin"

eval "\$(rbenv init -)"

cd "${APP_DIR}"

# 載入 .env
if [ -f .env ]; then
  set -a; source .env; set +a
fi

exec bundle exec rake ouou:pre_market
PRE_MARKET
  chmod +x bin/ouou-pre-market.sh
  ok "bin/ouou-pre-market.sh 更新完成"
}

# ============================================================
# PHASE 9：建置 Tailwind CSS
# ============================================================
phase9_build_assets() {
  step "建置 Tailwind CSS"
  set -a; source .env; set +a
  bundle exec rails tailwindcss:build
  ok "Tailwind CSS 建置完成"
}

# ============================================================
# PHASE 10：pm2 啟動
# ============================================================
phase10_pm2() {
  step "pm2 服務啟動"

  # 停止舊的 fairprice 相關 process（若存在）
  for proc in fairprice-rails fairprice-vite ouou-pre-market ouou-telegram-bot; do
    pm2 delete "$proc" &>/dev/null || true
  done

  set -a; source .env; set +a

  pm2 start ecosystem.config.cjs
  pm2 save
  ok "pm2 processes 已啟動並儲存"

  # 開機自啟
  echo ""
  if $HAS_SYSTEMD; then
    warn "設定 pm2 開機自啟需要 sudo，請手動執行以下指令："
    echo ""
    local node_path
    node_path="$(dirname "$(which node)")"
    local pm2_bin
    pm2_bin="$(which pm2)"
    echo -e "  ${BOLD}sudo env PATH=\$PATH:${node_path} ${pm2_bin} startup systemd -u ${INSTALL_USER} --hp ${HOME_DIR}${NC}"
    echo ""
  else
    # 無 systemd：.bashrc hook
    if ! grep -q 'pm2 resurrect' "${HOME_DIR}/.bashrc" 2>/dev/null; then
      cat >> "${HOME_DIR}/.bashrc" << 'BASHRC_PM2'

# pm2 auto-resurrect（由 fairprice install.sh 加入）
if command -v pm2 >/dev/null 2>&1; then
  pm2 resurrect >/dev/null 2>&1 || true
fi
BASHRC_PM2
      ok ".bashrc pm2 resurrect hook 加入完成"
    fi
    warn "無 systemd：開新 WSL terminal 時 pm2 會自動恢復服務"
    warn "建議在 /etc/wsl.conf 加入 [boot] systemd=true 以取得完整開機自啟支援"
  fi
}

# ============================================================
# PHASE 11：健康檢查
# ============================================================
phase11_health_check() {
  step "健康檢查"

  info "等待 Rails 啟動（最多 60 秒）..."
  local rails_ok=false
  for i in $(seq 1 60); do
    if curl -sf "http://localhost:${RAILS_PORT}/up" &>/dev/null; then
      ok "Rails server 就緒（${i}s）"
      rails_ok=true
      break
    fi
    printf "."
    sleep 1
  done
  echo ""

  if ! $rails_ok; then
    error "Rails server 60 秒內未回應"
    error "請執行：pm2 logs fairprice-rails --lines 50"
    exit 1
  fi

  info "等待 Vite dev server 啟動（最多 30 秒）..."
  for i in $(seq 1 30); do
    if curl -sf "http://localhost:${VITE_PORT}" &>/dev/null; then
      ok "Vite dev server 就緒（${i}s）"
      break
    fi
    printf "."
    sleep 1
  done
  echo ""
}

# ============================================================
# PHASE 12：完成畫面
# ============================================================
phase12_summary() {
  echo ""
  echo -e "${GREEN}${BOLD}"
  echo "  ╔══════════════════════════════════════════════════╗"
  echo "  ║          FairPrice 安裝完成！                    ║"
  echo "  ╠══════════════════════════════════════════════════╣"
  printf "  ║  App:      ${CYAN}http://localhost:%-4s${GREEN}${BOLD}                   ║\n" "${RAILS_PORT}"
  printf "  ║  Vite:     ${CYAN}http://localhost:%-4s${GREEN}${BOLD}                   ║\n" "${VITE_PORT}"
  printf "  ║  Lookbook: ${CYAN}http://localhost:%s/lookbook${GREEN}${BOLD}          ║\n" "${RAILS_PORT}"
  echo "  ╠══════════════════════════════════════════════════╣"
  echo "  ║  pm2 list                  查看服務狀態          ║"
  echo "  ║  pm2 logs fairprice-rails  Rails log             ║"
  echo "  ║  pm2 logs fairprice-vite   Vite log              ║"
  echo "  ╚══════════════════════════════════════════════════╝"
  echo -e "${NC}"

  echo ""
  pm2 list
}

# ============================================================
# main
# ============================================================
main() {
  clear
  echo -e "${BOLD}${BLUE}"
  echo "  ╔══════════════════════════════════════════════╗"
  echo "  ║   FairPrice WSL2 安裝程式  v${SCRIPT_VERSION}          ║"
  echo "  ║   Rails 8.1 + Vite + React + PostgreSQL      ║"
  echo "  ╚══════════════════════════════════════════════╝"
  echo -e "${NC}"

  phase0_preflight
  phase1_system_deps
  phase2_ruby
  phase3_nodejs
  phase4_env
  phase5_master_key
  phase6_deps
  phase7_database
  phase8_fix_paths
  phase9_build_assets
  phase10_pm2
  phase11_health_check
  phase12_summary
}

main "$@"
