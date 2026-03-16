# USER_MANUAL.md — FairPrice 使用手冊

## 概覽

FairPrice 是一套美股分析工具，整合公平價值估算、每日動能報告、投資組合追蹤與價格警示，運行於本機 port 3003。

---

## 工具一覽

| 工具 | 網址 | 功能簡述 |
|------|------|----------|
| FairPrice 估值 | `/` 或 `/valuations/:ticker` | 輸入股票代號，取得多方法公平價值估算 |
| Daily Momentum | `/momentum` | 自選股每日動能報告 + AI 分析 |
| Watchlist / 價格警示 | `/watchlist` | 設定股價到達目標時的 Telegram 推播 |
| Portfolio | `/portfolio` | 追蹤投資組合持股與損益 |
| JSON API | `/api/v1/valuations/:ticker` | 程式化取得估值結果 |

---

## 工具一：FairPrice 估值

### 基本操作

1. 在首頁搜尋框輸入美股代號（如 `AAPL`、`MSFT`）
2. 按 Enter 或點擊搜尋
3. 頁面跳轉至 `/valuations/AAPL`，顯示估值結果

### 估值方法

系統依股票類型自動選用適合的估值方法：

| 股票類型 | 適用方法 |
|----------|----------|
| 成長股 | DCF（現金流折現）、P/E、PEG |
| 配息股 | DDM（股息折現模型）、P/B |
| 成熟企業 | EV/EBITDA、P/E |

### 調整折現率

頁面右側可手動調整折現率（預設 10%），調整後即時重新計算。

### 解讀結果

- **公平價值**：各方法估算的合理股價
- **上漲空間**：現價相對公平價值的折價（正值 = 被低估）
- **分析師共識**：Finnhub 彙整的買/持/賣比例

---

## 工具二：Daily Momentum 每日動能報告

### 查看報告

前往 `/momentum`，系統自動載入當日所有自選股數據。

### 報告內容

| 區塊 | 說明 |
|------|------|
| VIX 指數 | 市場恐慌指標，> 30 為高波動警示 |
| 市場時段 | 盤前 / 盤中 / 盤後 / 休市 |
| 自選股表格 | 現價、漲跌幅、5日/20日動量、52週位置、成交量 vs 均量 |
| 新聞摘要 | 各股最新財經新聞 |
| 財報日曆 | 未來一週財報發布時程 |

### 歐歐 AI 分析

點擊個股旁的「歐歐分析」按鈕，觸發 AI 技術面分析：

- 分析結果以 SSE 串流方式逐字輸出
- 首次分析約需 10-30 秒；同一股票 3 小時內重複分析將直接讀取快取
- 分析完成後可點擊「下載 PNG」或「下載 PDF」儲存結果

### 修改自選股清單

編輯 `config/watchlist.yml`（不需修改程式碼）：

```yaml
symbols:
  - AAPL
  - MSFT
  - NVDA
  - TSLA
  - META
```

修改後重啟 server 生效。

---

## 工具三：Watchlist 價格警示

### 新增警示

1. 前往 `/watchlist/new`
2. 輸入股票代號、目標價、警示條件（高於 / 低於）
3. 儲存後，背景服務定期檢查股價並透過 Telegram 發送推播

### 管理警示

- 列表頁 `/watchlist` 顯示所有設定中的警示
- 可拖曳調整排序
- 切換啟用/停用不需刪除警示

---

## 工具四：Portfolio 投資組合

### 新增持股

1. 前往 `/portfolio`
2. 填入股票代號、持股數量、成本價
3. 系統即時顯示現值、損益與損益率

### OCR 匯入

點擊「OCR 匯入」，上傳持倉截圖，系統自動辨識並匯入持股資料。

---

## JSON API

### 取得估值

```
GET /api/v1/valuations/:ticker
```

範例：
```bash
curl http://localhost:3003/api/v1/valuations/AAPL
```

回應格式（JSON）：

```json
{
  "ticker": "AAPL",
  "current_price": 185.5,
  "valuations": [
    { "method": "DCF", "value": 210.0, "upside": 0.132 },
    { "method": "P/E", "value": 195.0, "upside": 0.051 }
  ],
  "recommendation": { "buy": 28, "hold": 10, "sell": 2 }
}
```

---

## 快速鍵 / 操作技巧

| 動作 | 方式 |
|------|------|
| 搜尋股票 | 在搜尋框輸入代號 + Enter |
| 切換工具 | 點擊左側 App Switcher 側欄 |
| 元件預覽 | 開發環境前往 `/lookbook` |
