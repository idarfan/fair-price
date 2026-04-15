# INSTALL.md — FairPrice 安裝指南

> **版本：20260415**

FairPrice 提供一鍵互動式安裝程式（`install.sh`），可在任何裝好 WSL2 的 Windows 電腦上自動完成所有環境設定。

---

## 版本記錄

### 20260415
- 修正首次安裝（無 `.env`）時 `cur_finnhub: unbound variable` 導致腳本提前退出
- 改用 `npm install --legacy-peer-deps` 解決 `@vitejs/plugin-react` 與 `vite` 版本衝突
- 修正 `pg_hba.conf` 設定：無密碼時改用 `trust`；直接改既有行而非插入新行
- 測試資料庫 schema 載入失敗時改為警告而非中斷安裝
- Vite dev server 加入 `--host 0.0.0.0`，Windows 瀏覽器可正常存取 `localhost:3036`
- `pm2 startup` 提示指令加上引號，避免 WSL2 PATH 含空格時出現 `env: 'Files': No such file or directory`

---

## 安裝前準備：請先申請以下 API Keys

> ⚠️ **安裝程式執行到一半會暫停要求輸入 API Key，請在開始安裝前先申請好。**
> 申請帳號後即可免費使用，無需信用卡。

### 必填（缺少任一項則核心功能無法使用）

#### FINNHUB_API_KEY — 股票即時報價與財務數據
- **用途**：抓取股票報價、財務指標、公司資訊、期權鏈、收益日期等
- **申請網址**：[https://finnhub.io](https://finnhub.io)
- **申請步驟**：右上角 **Sign Up** → 選 Free 方案（免費，每分鐘 60 次請求）→ 登入後至 [Dashboard](https://finnhub.io/dashboard) 複製 API Key

#### GROQ_API_KEY — AI 分析與圖片辨識
- **用途**：股票基本面 / 技術面 AI 分析、持股截圖 OCR 辨識、期權截圖解析、每日盤前報告生成
- **申請網址**：[https://console.groq.com](https://console.groq.com)
- **申請步驟**：Sign Up（可用 Google 帳號）→ 左側 **API Keys** → **Create API Key** → 複製（免費，有每日 Token 額度）

---

### 選填（不填則停用對應功能，其餘功能不受影響）

#### TELEGRAM_BOT_TOKEN — Telegram 推播機器人
- **用途**：股價警示推播、每日盤前報告自動發送至 Telegram 群組
- **申請步驟**：
  1. 在 Telegram 搜尋 **@BotFather**
  2. 發送 `/newbot`，依提示輸入 Bot 名稱
  3. 複製 BotFather 回傳的 token（格式：`1234567890:ABCdef...`）

#### TELEGRAM_CHAT_ID — 推播目標（個人）
- **用途**：股價警示推播的接收對象（你的個人 Telegram）
- **取得方式**：與你的 Bot 發送任意訊息後，開啟 `https://api.telegram.org/bot<你的TOKEN>/getUpdates`，在 JSON 中找 `"chat":{"id":...}` 的數字

#### OUOU_TELEGRAM_CHAT_ID — 推播目標（群組）
- **用途**：每日盤前報告自動發送至指定 Telegram 群組
- **取得方式**：將 Bot 加入群組後，同樣用 `/getUpdates` 取得群組 Chat ID（群組 ID 為負數，例如 `-1001234567890`）

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

## 流程概覽

```
提供方（現有機器）             新電腦
──────────────────────         ──────────────────────────────
bash package.sh                1. 複製隨身碟上的 fairprice-installer/
→ ~/fairprice-installer/  ──→  2. cd ~/fairprice-installer
  複製到隨身碟                  3. bash install.sh
                               4. 填入自己的 API Keys → 完成
```

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

後續所有指令皆在 **WSL2 Ubuntu 終端機**內執行。

---

## 二、（建議）啟用 WSL2 systemd

```bash
echo -e '[boot]\nsystemd=true' | sudo tee /etc/wsl.conf
```

然後在 PowerShell 重啟 WSL：

```powershell
wsl --shutdown
```

重新開啟 Ubuntu。啟用後 FairPrice 服務可在開機後自動啟動。

---

## 三、取得安裝目錄

將隨身碟插入新電腦，把隨身碟上的 `fairprice-installer/` 目錄複製到 WSL2 家目錄：

```bash
# 查詢隨身碟掛載點（通常是 /mnt/d、/mnt/e 等）
ls /mnt/

# 複製安裝目錄（依實際掛載點調整）
cp -r /mnt/<隨身碟>/fairprice-installer ~/
```

> **Windows 檔案總管方式**：也可以直接在檔案總管把 `fairprice-installer` 資料夾拖放到
> `\\wsl$\Ubuntu\home\<你的使用者名稱>\`

---

## 四、執行安裝程式

```bash
cd ~/fairprice-installer
bash install.sh
```

安裝程式會以互動方式引導你完成所有步驟。

---

## 五、安裝過程說明

### 自動執行的步驟（無需操作）

| 步驟 | 說明 | 所需時間 |
|------|------|---------|
| 系統套件 | 安裝 build-essential、libpq-dev 等 | 1–3 分鐘 |
| Ruby 4.0.1 | 編譯安裝（首次） | **10–20 分鐘** |
| Node.js LTS | 安裝 Node.js v22 與 pm2 | 1–2 分鐘 |
| gem / npm | 安裝 Ruby 與前端依賴 | 3–5 分鐘 |
| 資料庫 | 建立 PostgreSQL 資料庫並 migrate | < 1 分鐘 |

### 需要填入的 API Keys

```
━━━ API Keys 設定 ━━━
FINNHUB_API_KEY：至 https://finnhub.io 免費申請
GROQ_API_KEY：  至 https://console.groq.com 免費申請

[必填] FINNHUB_API_KEY: （輸入後不顯示）
[必填] GROQ_API_KEY:
[選填] TELEGRAM_BOT_TOKEN  (直接 Enter 跳過):
[選填] TELEGRAM_CHAT_ID:
[選填] OUOU_TELEGRAM_CHAT_ID:
```

- **FINNHUB_API_KEY** 和 **GROQ_API_KEY** 為必填，皆提供免費方案（見附錄）
- Telegram 相關為選填，略過則停用價格警示與盤前報告功能
- 資料庫設定直接按 Enter 保留預設值即可

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
╚══════════════════════════════════════════════════╝
```

開啟 Windows 瀏覽器，前往 `http://localhost:3003` 即可使用 FairPrice。

---

## 七、設定開機自動啟動（有 systemd）

若已依第二步啟用 systemd，安裝完成後畫面會顯示一行指令，例如：

```
sudo env PATH=$PATH:/usr/bin /home/<user>/.npm-global/bin/pm2 startup systemd -u <user> --hp /home/<user>
```

**將此指令複製貼上並執行**，pm2 便會在每次 WSL2 啟動後自動開啟所有服務。

---

## 八、日常操作指令

```bash
pm2 list                        # 查看所有服務狀態
pm2 logs fairprice-rails        # Rails log（即時）
pm2 logs fairprice-vite         # Vite log
pm2 restart fairprice-rails     # 重啟 Rails
pm2 restart all                 # 重啟所有服務
pm2 stop all                    # 停止所有服務
```

---

## 九、重新安裝或更新

直接再次執行安裝程式即可，已完成的步驟會自動跳過：

```bash
cd ~/fairprice-installer
bash install.sh
```

執行到 API Keys 設定時，選擇 `N` 可保留原本的 Keys。

---

## 十、常見問題

### Ruby 4.0.1 編譯失敗

確認 Ubuntu 版本為 22.04 以上：

```bash
lsb_release -rs
```

若版本過舊，建議在 PowerShell 重新安裝 Ubuntu 22.04：

```powershell
wsl --install -d Ubuntu-22.04
```

### pm2 啟動後 Rails 無回應

```bash
pm2 logs fairprice-rails --lines 30 --nostream
```

| 常見原因 | 解法 |
|---------|------|
| PostgreSQL 未啟動 | `sudo service postgresql start` |
| .env 遺失 | 重新執行 `bash install.sh` |
| Port 3003 被佔用 | `ss -tlnp \| grep 3003` |

### Finnhub API 回應 403

確認 `.env` 中的 `FINNHUB_API_KEY` 正確，且帳號仍在免費額度內（每分鐘 60 次請求上限）。

### 如何修改 API Keys

```bash
nano ~/fairprice-installer/.env   # Ctrl+X → Y → Enter 儲存
pm2 restart fairprice-rails
```

---

## 附錄：API Keys 申請說明

### FINNHUB_API_KEY（必填）

1. 前往 [https://finnhub.io](https://finnhub.io)
2. 右上角 **Sign Up** → 選擇 Free 方案
3. 登入後至 [Dashboard](https://finnhub.io/dashboard) 複製 API Key

免費方案：每分鐘 60 次請求，足夠個人使用。

### GROQ_API_KEY（必填）

1. 前往 [https://console.groq.com](https://console.groq.com)
2. Sign Up（可用 Google 帳號登入）
3. 左側 **API Keys** → **Create API Key** → 複製

免費方案提供每日 Token 額度，供 AI 分析與 OCR 使用。

### TELEGRAM_BOT_TOKEN（選填）

1. 在 Telegram 搜尋 **@BotFather**
2. 發送 `/newbot`，依提示設定 Bot 名稱
3. 複製提供的 token（格式：`1234567890:ABC...`）

### TELEGRAM_CHAT_ID（選填）

1. 與你的 Bot 發送任意訊息
2. 開啟瀏覽器前往：`https://api.telegram.org/bot<你的TOKEN>/getUpdates`
3. 在 JSON 回應中找到 `"chat":{"id":...}` 的數字即為 Chat ID
