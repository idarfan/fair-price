# INSTALL.md — FairPrice 安裝指南

## 系統需求

| 項目 | 版本 |
|------|------|
| Ruby | >= 3.2（建議用 rbenv 管理）|
| Rails | ~> 8.1.2 |
| Node.js | >= 18（Tailwind CLI、Vite 需要）|
| npm | >= 9 |
| PostgreSQL | >= 14 |
| pm2 | >= 5（正式環境 process manager）|
| OS | Linux（建議 Ubuntu 22.04 / Debian 12）|

---

## 零、前置安裝

### Ruby（rbenv）

```bash
# 安裝 rbenv
curl -fsSL https://github.com/rbenv/rbenv-installer/raw/main/bin/rbenv-installer | bash

# 加入 shell 設定（以 bash 為例）
echo 'export PATH="$HOME/.rbenv/bin:$PATH"' >> ~/.bashrc
echo 'eval "$(rbenv init -)"' >> ~/.bashrc
source ~/.bashrc

# 安裝專案所需版本（確認 .ruby-version 中的版本號）
rbenv install $(cat .ruby-version)
```

### Node.js（nvm）

```bash
# 安裝 nvm
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
source ~/.bashrc

# 安裝 Node 18+
nvm install 18
nvm use 18
```

### pm2（正式環境）

```bash
npm install -g pm2
```

---

## 一、從 GitHub 下載專案

```bash
# SSH（推薦，需先設定 SSH key）
git clone git@github.com:idarfan/fair-price.git fairprice

# HTTPS（無需 SSH key）
git clone https://github.com/idarfan/fair-price.git fairprice

cd fairprice
```

> 若尚未設定 GitHub SSH key，請參考 [GitHub 官方說明](https://docs.github.com/en/authentication/connecting-to-github-with-ssh)，或改用 HTTPS 方式。

---

## 二、安裝 Ruby 相依套件

```bash
bundle install
```

主要 gem：

| Gem | 用途 |
|-----|------|
| `rails ~> 8.1` | 框架本體 |
| `propshaft` | 靜態資源管線 |
| `phlex-rails ~> 2.0` | UI 元件系統 |
| `tailwindcss-rails ~> 4.0` | Tailwind CSS 本地編譯 |
| `kramdown` + `kramdown-parser-gfm` | 伺服器端 Markdown 渲染 |
| `httparty ~> 0.22` | HTTP 客戶端（呼叫 Finnhub / Yahoo Finance）|
| `pg ~> 1.5` | PostgreSQL 連線（Watchlist / Portfolio）|
| `lookbook >= 2.3` | 元件預覽（開發環境）|
| `ruby-lsp` | Ruby 語言伺服器（開發環境）|

---

## 三、安裝前端相依套件

```bash
npm install
```

---

## 四、設定環境變數

複製範本並填入實際值：

```bash
cp .env.example .env
```

`.env` 必填項目：

```env
# Finnhub API Key（從 https://finnhub.io 免費申請）
FINNHUB_API_KEY=your_key_here

# Anthropic API Key（歐歐分析功能）
ANTHROPIC_API_KEY=your_key_here

# Telegram Bot（價格警示推播，選填）
TELEGRAM_BOT_TOKEN=your_token_here
TELEGRAM_CHAT_ID=your_chat_id_here

# PostgreSQL（Watchlist / Portfolio 功能）
DATABASE_URL=postgresql://user:password@localhost/fairprice_development
```

---

## 五、資料庫初始化

```bash
bundle exec rails db:create
bundle exec rails db:migrate
```

---

## 六、編譯 Tailwind CSS

```bash
bundle exec rails tailwindcss:build
```

---

## 七、啟動伺服器

### 開發環境（foreman，單機本地）

```bash
bin/dev
```

`bin/dev` 會透過 `Procfile.dev` 同時啟動 Rails（port 3003）、Tailwind watch、Vite dev server（port 3036）。

### 正式環境（pm2）

專案使用 pm2 統一管理 Rails 與 Vite，設定檔為 `ecosystem.config.cjs`。

#### 1. 調整路徑設定

`ecosystem.config.cjs` 與 `bin/start-rails.sh` 內含硬編碼的絕對路徑，**在他處安裝時必須修改**：

`ecosystem.config.cjs`：
```js
cwd: '/home/<your-user>/fairprice',   // 改成實際路徑
PATH: '/home/<your-user>/.rbenv/shims:/home/<your-user>/.rbenv/bin:/usr/bin:/bin',
RBENV_ROOT: '/home/<your-user>/.rbenv',
```

`bin/start-rails.sh`：
```bash
APP_DIR="/home/<your-user>/fairprice"  // 改成實際路徑
```

#### 2. 啟動

```bash
pm2 start ecosystem.config.cjs
pm2 save          # 儲存 process 清單，重開機後自動恢復
pm2 startup       # 依照提示執行輸出的指令，設定開機自啟
```

服務啟動後監聽於 **port 3003**（Rails）和 **port 3036**（Vite）。

---

## 八、確認安裝成功

```bash
# Boot 檢查
bundle exec rails runner "puts 'Boot OK'"

# pm2 狀態
pm2 list
pm2 logs fairprice-rails --lines 15 --nostream

# 確認路由
bundle exec rails routes
```

開啟瀏覽器：
- 主頁：`http://localhost:3003`
- 元件預覽：`http://localhost:3003/lookbook`（開發環境）

---

## 九、Lint 檢查

```bash
bundle exec rubocop        # 檢查
bundle exec rubocop -a     # 自動修正
```

---

## 常見問題

### Tailwind 樣式沒有套用

確認已執行 `bundle exec rails tailwindcss:build`，並在 `app/views/layouts/application.html.erb` 引用 `stylesheet_link_tag "tailwind"`。

### Markdown 表格顯示異常

確認 `kramdown-parser-gfm` 已安裝，且所有呼叫皆使用 `input: "GFM"` 選項：
```ruby
Kramdown::Document.new(text, input: "GFM").to_html
```

修改渲染邏輯後需重啟 server 並清除 cache：
```bash
pm2 restart fairprice-rails
bundle exec rails runner "Rails.cache.clear"
```

### Finnhub API 回應 403

確認 `.env` 中 `FINNHUB_API_KEY` 填寫正確，且帳號尚在免費額度內。

### pm2 啟動後 Rails 無回應

查看啟動日誌：
```bash
pm2 logs fairprice-rails --lines 30 --nostream
```

常見原因：`ecosystem.config.cjs` 路徑未更新、rbenv 未正確初始化、PostgreSQL 未啟動。
