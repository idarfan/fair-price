# INSTALL.md — FairPrice 安裝指南

FairPrice 提供一鍵互動式安裝程式（`install.sh`），可在任何裝好 WSL2 的 Windows 電腦上自動完成所有環境設定。

---

## 系統需求

| 項目 | 需求 |
|------|------|
| 作業系統 | Windows 10（21H2 以上）或 Windows 11 |
| WSL2 | Ubuntu 22.04 LTS（建議）|
| 磁碟空間 | 至少 4 GB 可用空間 |
| 網路 | 安裝過程需要網路（下載 Ruby、Node.js 等依賴）|

> 安裝程式會自動安裝 Ruby 4.0.1、Node.js LTS、PostgreSQL、pm2，**無需事先手動安裝**。

---

## 一、在 Windows 安裝 WSL2（新電腦必做）

以**系統管理員**身分開啟 PowerShell，執行：

```powershell
wsl --install
```

安裝完成後**重新啟動電腦**，Ubuntu 會在重啟後自動開啟。
依提示設定 Linux 使用者名稱與密碼即完成。

> 若已安裝舊版 WSL1，執行 `wsl --set-default-version 2` 升級。
> 詳細說明：[Microsoft WSL 官方文件](https://learn.microsoft.com/zh-tw/windows/wsl/install)

---

## 二、（建議）啟用 WSL2 systemd

開啟 Ubuntu 終端機，執行：

```bash
echo -e '[boot]\nsystemd=true' | sudo tee /etc/wsl.conf
```

然後在 PowerShell 重啟 WSL：

```powershell
wsl --shutdown
```

重新開啟 Ubuntu。啟用 systemd 後，FairPrice 服務可在開機後自動啟動。

---

## 三、取得安裝包

向提供者取得 `fairprice-bundle.tar.gz`，複製到 WSL2 家目錄。

**常見複製方式：**

```bash
# 方式 A：從 Windows 檔案總管拖放到 WSL 家目錄
# 路徑：\\wsl$\Ubuntu\home\<你的使用者名稱>

# 方式 B：SCP（從提供者的機器下載）
scp <提供者IP>:~/fairprice-bundle.tar.gz ~/
```

---

## 四、執行安裝程式

在 WSL2 Ubuntu 終端機中執行：

```bash
cd ~
tar xzf fairprice-bundle.tar.gz
cd fairprice-bundle
bash install.sh
```

安裝程式將以互動方式引導你完成所有步驟。

---

## 五、安裝過程說明

安裝程式會依序執行以下步驟，每步驟完成後顯示 `[ OK ]`。

### 步驟 1–3：自動安裝（無需操作）
- 安裝系統套件（`build-essential`、`libpq-dev` 等）
- 編譯安裝 Ruby 4.0.1（**約需 10–20 分鐘**，依電腦速度而定）
- 安裝 Node.js LTS 與 pm2

### 步驟 4：填入 API Keys（必須操作）

安裝程式會顯示申請連結並逐一詢問：

```
━━━ API Keys 設定 ━━━
FINNHUB_API_KEY：至 https://finnhub.io 免費申請
GROQ_API_KEY：  至 https://console.groq.com 免費申請

[必填] FINNHUB_API_KEY: （輸入後不顯示）
[必填] GROQ_API_KEY:
[選填] TELEGRAM_BOT_TOKEN  (直接 Enter 跳過):
[選填] TELEGRAM_CHAT_ID:
[選填] OUOU_TELEGRAM_CHAT_ID:

━━━ 資料庫設定 ━━━
DB_HOST [localhost]:
DB_PORT [5432]:
DB_USER [你的使用者名稱]:
DB_PASSWORD (可留空):
```

- **FINNHUB_API_KEY** 和 **GROQ_API_KEY** 為必填，皆提供免費方案
- Telegram 相關為選填，略過則停用價格警示與盤前報告功能
- 資料庫設定保持預設值（直接 Enter）即可

### 步驟 5–10：自動完成（無需操作）
- 安裝 Ruby gem 與 npm 套件
- 建立並初始化 PostgreSQL 資料庫
- 建置 Tailwind CSS
- 啟動 pm2 服務

---

## 六、確認安裝成功

安裝完成後畫面會顯示：

```
╔══════════════════════════════════════════════════╗
║          FairPrice 安裝完成！                    ║
╠══════════════════════════════════════════════════╣
║  App:      http://localhost:3003                 ║
║  Vite:     http://localhost:3036                 ║
║  Lookbook: http://localhost:3003/lookbook        ║
╠══════════════════════════════════════════════════╣
║  pm2 list                  查看服務狀態          ║
║  pm2 logs fairprice-rails  Rails log             ║
╚══════════════════════════════════════════════════╝
```

開啟 Windows 瀏覽器，前往：

```
http://localhost:3003
```

即可使用 FairPrice。

---

## 七、設定開機自動啟動（有 systemd）

若已依第二步啟用 systemd，安裝完成後畫面會顯示一行指令，例如：

```
sudo env PATH=$PATH:/usr/bin /home/idarfan/.npm-global/bin/pm2 startup systemd -u idarfan --hp /home/idarfan
```

**將此指令複製貼上並執行**，pm2 便會在每次 WSL2 啟動後自動開啟所有服務。

---

## 八、日常操作指令

```bash
# 查看所有服務狀態
pm2 list

# 查看 Rails log（即時）
pm2 logs fairprice-rails

# 查看 Vite log
pm2 logs fairprice-vite

# 重啟 Rails
pm2 restart fairprice-rails

# 停止所有服務
pm2 stop all

# 重新啟動所有服務
pm2 restart all
```

---

## 九、重新安裝或更新

如需重新執行安裝（例如取得新版本的 bundle），直接再次執行：

```bash
cd fairprice-bundle
bash install.sh
```

安裝程式為冪等（idempotent）設計，已完成的步驟會自動跳過。
執行到 API Keys 設定時，選擇 `N` 可保留原本的 Key。

---

## 十、常見問題

### Ruby 4.0.1 編譯失敗

**原因**：缺少 OpenSSL 3.x 或其他編譯依賴。

**解法**：確認 Ubuntu 版本為 22.04 以上（執行 `lsb_release -rs` 確認）。若版本過舊，建議重新安裝 Ubuntu 22.04：

```powershell
# PowerShell
wsl --install -d Ubuntu-22.04
```

---

### pm2 啟動後 Rails 無回應

**診斷**：

```bash
pm2 logs fairprice-rails --lines 30 --nostream
```

**常見原因與解法**：

| 原因 | 解法 |
|------|------|
| PostgreSQL 未啟動 | `sudo service postgresql start` |
| .env 遺失 | 重新執行 `bash install.sh` |
| Port 3003 被佔用 | `ss -tlnp \| grep 3003` 確認 |

---

### Finnhub API 回應 403

確認 `.env` 中的 `FINNHUB_API_KEY` 正確，且帳號仍在免費額度內（每分鐘 60 次請求上限）。

---

### Tailwind 樣式沒有套用

確認 Tailwind CSS 已完成建置：

```bash
cd ~/fairprice-bundle
bash -c 'source ~/.bashrc && bundle exec rails tailwindcss:build'
pm2 restart fairprice-rails
```

---

### 如何修改 API Keys

直接編輯 `.env` 檔案後重啟 Rails：

```bash
nano ~/fairprice-bundle/.env   # 修改後 Ctrl+X → Y → Enter 儲存
pm2 restart fairprice-rails
```

---

## 附錄：API Keys 申請說明

### FINNHUB_API_KEY（必填）

1. 前往 [https://finnhub.io](https://finnhub.io)
2. 點選右上角 **Sign Up**，選擇 Free 方案
3. 登入後至 [Dashboard](https://finnhub.io/dashboard) 複製 API Key

免費方案限制：每分鐘 60 次請求，已足夠個人使用。

### GROQ_API_KEY（必填）

1. 前往 [https://console.groq.com](https://console.groq.com)
2. Sign Up（可用 Google 帳號登入）
3. 左側選單 **API Keys** → **Create API Key** → 複製

免費方案提供每日 Token 額度，供 AI 分析與 OCR 功能使用。

### TELEGRAM_BOT_TOKEN（選填）

1. 在 Telegram 搜尋 **@BotFather**
2. 發送 `/newbot`，依提示設定 Bot 名稱
3. 複製提供的 token（格式：`1234567890:ABC...`）

### TELEGRAM_CHAT_ID（選填）

1. 與你的 Bot 發送任意訊息
2. 開啟瀏覽器前往：`https://api.telegram.org/bot<你的TOKEN>/getUpdates`
3. 在 JSON 回應中找到 `"chat":{"id":...}` 的數字即為 Chat ID
