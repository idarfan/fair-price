# CHANGELOG — FairPrice

版號格式：`YYYYMMDD`（與 fairprice-installer 同步）

---

## v20260420

### 新增
- 進入頁顯示版本號徽章（`v20260420`）
- 全站 footer 加入版本號
- 本 CHANGELOG 文件

### 期權鏈（Options）
- CBOE API 取代 yfinance，補足深度 OTM 行權價缺口
- Calls / Puts 切換篩選，單側高亮並隱藏對側欄位
- 新增欄位：Distance、Rel dist、Spread、Theor、Bid%、Ask%、Ann bid%
- Tippy + KaTeX 豐富 hover tooltip（含公式說明）
- 現價改為 Header badge，表格移除分隔行
- 側欄可摺疊（Panel 尺寸 prop 改用字串 % 格式）
- 修正水平溢出與中文欄位標籤

### 架構文件
- 架構圖納入期權鏈新元件與 CBOE / External API 層
- 同步更新 excalidraw 原始檔與 SVG 版本

---

## v20260415

### 安裝程式修正
- 修正首次安裝（無 `.env`）時 `cur_finnhub: unbound variable` 導致腳本提前退出
- 改用 `npm install --legacy-peer-deps` 解決 `@vitejs/plugin-react` 與 `vite` 版本衝突
- 修正 `pg_hba.conf` 設定：無密碼時改用 `trust`；直接改既有行而非插入新行
- 測試資料庫 schema 載入失敗時改為警告而非中斷安裝
- Vite dev server 加入 `--host 0.0.0.0`，Windows 瀏覽器可正常存取 `localhost:3036`
- `pm2 startup` 提示指令加上引號，避免 WSL2 PATH 含空格時出現 `env: 'Files': No such file or directory`

---

## 歷史版本

更早的變更記錄請參考 `git log` 或 `fairprice-installer/docs/INSTALL.md` 的版本記錄章節。
