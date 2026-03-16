# INSTALL.md — FairPrice 安裝指南

## 系統需求

| 項目 | 版本 |
|------|------|
| Ruby | >= 3.2 |
| Rails | ~> 8.1.2 |
| Node.js | >= 18（Tailwind CLI 需要） |
| PostgreSQL | >= 14 |
| OS | Linux（建議 Ubuntu 22.04 / Debian 12） |

---

## 一、複製專案

```bash
git clone <repo-url> fairprice
cd fairprice
```

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
| `httparty ~> 0.22` | HTTP 客戶端（呼叫 Finnhub / Yahoo Finance） |
| `pg ~> 1.5` | PostgreSQL 連線（Watchlist / Portfolio） |
| `lookbook >= 2.3` | 元件預覽（開發環境） |
| `ruby-lsp` | Ruby 語言伺服器（開發環境，提供 IDE 語意分析） |

---

## 三、設定環境變數

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

## 四、資料庫初始化

```bash
bundle exec rails db:create
bundle exec rails db:migrate
```

---

## 五、編譯 Tailwind CSS

```bash
bundle exec rails tailwindcss:build
```

> 開發時可改用 `bin/dev` 自動監聽變更並重新編譯。

---

## 六、啟動伺服器

### 開發環境

```bash
bin/dev
```

### 正式環境（systemd user service）

```bash
# 安裝 service 設定（路徑：~/.config/systemd/user/fairprice.service）
systemctl --user daemon-reload
systemctl --user enable fairprice
systemctl --user start  fairprice
```

服務啟動後監聽於 **port 3003**。

---

## 七、確認安裝成功

```bash
# Boot 檢查
bundle exec rails runner "puts 'Boot OK'"

# 查看服務狀態
systemctl --user status fairprice

# 查看最近 30 行 log
journalctl --user -u fairprice -n 30

# 確認路由
bundle exec rails routes
```

開啟瀏覽器：
- 主頁：`http://localhost:3003`
- 元件預覽：`http://localhost:3003/lookbook`（開發環境）

---

## 八、Lint 檢查

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
systemctl --user restart fairprice
bundle exec rails runner "Rails.cache.clear"
```

### Finnhub API 回應 403

確認 `.env` 中 `FINNHUB_API_KEY` 填寫正確，且帳號尚在免費額度內。
