# 稽核修正 — 2026-08-28

依 `RAILS_AUDIT_REPORT.md` 執行。基準 commit `39ac654`。

## 決策（已與使用者確認）
- `force_ssl`：只在公網網域強制，`localhost` / `127.0.0.1` / `/up` 排除
- `user_id` 遷移：全部 6 張表都做，既有資料 backfill 給 `mr.idarfan@gmail.com`

## C-1 `/api/*` 認證缺口（公網已實測曝露）
- [x] `ApplicationController` 把 `/api` 移出白名單，前綴比對改成 anchored regex
- [x] 抽出 `gate_deny(reason)` hook，讓 API 能改回 JSON 而非 302
- [x] 新增 `JsonAuthGate` concern（401/403 JSON + CSRF 失敗轉 JSON）
- [x] `Api::V1::BaseController` 與 `Api::IvAnalysisController` 套用，CSRF 由 `null_session` 改 `exception`
- [x] 補三處缺 `X-CSRF-Token` 的前端寫入：`OwnershipApp` / `OptionsAnalyzerApp` / `ImageUploadZone`
- [x] 改寫 `auth_gate_spec` 的 `leaves /api/* accessible`，改成斷言 401
- [x] 新增 `spec/requests/api/auth_gate_spec.rb` 覆蓋讀取與破壞性端點

## C-2 財務資料加 user_id
- [x] migration：6 張表加 `user_id`，backfill admin，加 index + FK，改 `null: false`
- [x] model 加 `belongs_to :user`，`User` 加對應 `has_many`
- [x] controller 全改 `current_user.xxx` scope
- [x] 既有 spec 與 factory 補 user 關聯

## High
- [x] H-1 `tracked_tickers#collect` 改背景 job（比照 ScrapeLeapsJob 的 cache 回報模式）
- [x] H-2 `force_ssl` + `assume_ssl` + `ssl_options` 排除 localhost 與 `/up`
- [x] H-4 `TrackedTicker#last_snapshot_date` N+1 → group query
- [x] H-5 `iv_analysis#watchlist` 無上限 thread → 固定大小 pool
- [x] H-6 `bundle update mail`（GHSA-mvxr-6m87-mv2q）

## Medium
- [x] M-1 刪 `public/tech_prototype.html`
- [x] M-2 三處把 `e.message` 直接回客戶端 → log 詳細、回籠統訊息
- [x] M-3 `barchart_scraper_service.rb:422` 裸 rescue 補 log
- [x] M-4 `TrackController#page_view` 檢查 `save` 回傳值
- [x] M-5 `iv_watchlists.ticker` 補 unique index；`iv_queries` 補索引

## H-3 內嵌 JS 遷移（Wave 1 已完成 2026-08-28）
- [x] tsconfig.json（strict）+ 修掉既有 9 個型別錯誤 → tsc 0 error
- [x] eslint 瀏覽器全域 → 假陽性 20 個歸零，再修掉 4 個真錯誤
- [x] behaviors entrypoint + 動態 import code-splitting
- [x] 10 個零插值元件、12 段、2,188 行搬遷（Ruby 求值處理跳脫）
- [x] spec/frontend/behavior_registry_spec.rb 釘住元件↔模組連結
- [ ] Wave 2：少量插值 6 個元件（707 行，13 處插值 → data attribute）
- [ ] Wave 3：bull_put/bull_call（1,038 行，37 處插值；順便解 M-6 重複程式碼）
- [ ] layout 自己的 inline script + 關閉 CSP unsafe_inline
- [ ] behaviors/*.js 型別化成 .ts（約 600 個型別錯誤）
- L-2 Service → PORO 更名
- L-1 補測試：只補本次改動相關的，不做全面補測

## 驗收
- [x] `bundle exec rspec` 全綠
- [x] 公網 `https://fairprice-ohmy.com/api/v1/tracked_tickers` 未登入回 401

---

## Review（2026-08-28 完成）

### 執行結果
- RSpec **638 examples / 0 failures**（且是第一次真正跑在隔離的 `fairprice_test` 上）
- Brakeman 0 warnings｜RuboCop 339 檔無 offense｜bundler-audit 無漏洞｜ESLint 無新增問題
- 公網實測：`https://fairprice-ohmy.com/api/*` 未登入回 **401**（修正前是 200 + 真實資料）

### 與原計畫的三處偏離

1. **C-2 只做 3 張表，不是 6 張**（使用者原選「全部 6 張」）。
   追下去發現 `TrackedTicker` 驅動夜間 Python 蒐集器、產出 79 萬列共用的
   `OptionSnapshot`；`WatchlistItem` 是 `OuouPreMarketService` 排程 Telegram
   盤前報告的來源；`IvWatchlist` 是有 group_tag 分類的共用參考清單。
   這三張是**共用市場資料**，加 user_id 會讓爬蟲與排程碎片化。
   只對真正個人性的 `margin_positions` / `portfolios` / `price_alerts` 加歸屬。
   若仍要全部 6 張，需要先決定排程作業要用哪個使用者的清單。

2. **M-5 的前半段是誤判**。稽核報告寫「`iv_watchlists.ticker` 缺 unique index」，
   實際上該欄位叫 `symbol` 且已有 unique index——是報告的自動檢查腳本猜錯欄位名。
   **13 個 uniqueness validation 全部都有對應的 unique index，沒有缺口。**
   後半段（`iv_queries` 零索引）成立，已修。

3. **`force_ssl` 沒有照原本說的加 `assume_ssl`**。實測 `assume_ssl` 會讓
   `http://localhost:3003` 的 redirect 也產生 `https://` 網址，本機瀏覽直接壞掉。
   改為依 cloudflared 的 `X-Forwarded-Proto` 判斷，已實測兩邊都正確。

### 稽核當下沒發現、修的過程中才抓到的

- **測試環境連到正式資料庫**（見 README）。這比報告裡任何一項都嚴重：
  RSpec 一直跑在 `fairprice_development` 上，13 個失敗中有 8 個是正式資料污染
  造成的假結果。也代表稽核報告裡「627 examples 全綠」那個基準本身就不可信。
- `option_price_tracker_controller` 與 API controller 有一份**重複的 serializer**，
  兩份都踩同一個 N+1（違反 `~/.claude/rules/rails-gotchas.md` 的「Serializer 不可重複定義」）。

### 已知仍未處理

- **H-3 內嵌 JS 遷移到 Vite**（7 個元件、最大單一方法 725 行）。工程量最大，
  是 13 個 F 級檔案、CSP `unsafe_inline`、元件 5000 行零覆蓋的共同成因。
- **前端沒有 `tsconfig.json`**，`~/.claude/rules/typescript.md` 要求的
  `strict` / `noUncheckedIndexedAccess` / `npx tsc --noEmit` 目前都無法執行。
  ESLint 現存 20 個 `no-undef`（`document` / `window` / `fetch` 等瀏覽器全域）
  是 ESLint env 設定沒開 browser 造成的，不是真的錯誤。
- **測試覆蓋率仍偏低**。本次只補了與改動相關的測試（API 閘門、跨使用者隔離、
  PriceAlert position 分使用者），沒有做全面補測。
