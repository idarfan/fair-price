# database_consistency 36 項處置計畫（2026-08-30）

## 盤點結論：24 項該修，12 項不該修

「全部修掉」不是正確目標——其中 12 項若照著修，會產生**永遠不會執行的驗證器**，
反而製造「這裡有驗證」的假象。

---

## A. 不修，寫進設定檔並記錄理由（12 項）

### A-1　8 個 snapshot 表的 UniqueIndexChecker

`StrikeChainSnapshot` / `SkewRankIntraday` / `SkewRankDaily` / `PmccShortCallSnapshot` /
`OptionSnapshot` / `LeapsOptionChainSnapshot` / `BcvsExpirationSnapshot` / `BcvsChainSnapshot`

已查證全部走 `upsert` / `insert_all` 寫入（`barchart_scraper_service.rb:608/677/699`、
`skew_intraday_snapshot_service.rb:31`、`skew_snapshot_service.rb:22`），
**這兩個 API 完全跳過 ActiveRecord 驗證**。加上去的驗證器永遠不會執行。

`OptionSnapshot` 更是無解——索引是
`(tracked_ticker_id, date_trunc('hour', snapped_at), contract_symbol)`，
Rails 的 uniqueness 驗證器無法表達 `date_trunc` 這種運算式。

### A-2　保留給 B 段處理的 4 項

（見下）

---

## B. 用「修對」的方式消掉 8 項（4 UniqueIndex + 4 MissingUniqueIndex）

這 8 項其實是**同一個根因的兩面**：`WatchlistItem` / `WatchedTicker` /
`TrackedTicker` / `IvWatchlist` 都寫 `uniqueness: { case_sensitive: false }`，
於是 database_consistency 認為「驗證器管的是 `lower(symbol)`，但索引是 `symbol`」，
同時報「索引沒有對應驗證器」與「應該建 `lower()` 索引」。

正解不是加索引，而是**拿掉 `case_sensitive: false`**：

- 這四個 model 存檔前都會 `upcase`，DB 裡只有大寫，比對大小寫毫無意義
- `case_sensitive: false` 會產生 `LOWER(symbol) = LOWER($1)` 查詢，
  **用不到 `(user_id, symbol)` btree 索引**——是純粹的浪費
- 已查證：四張表現有資料**非大寫筆數皆為 0**

⚠️ 但 `TrackedTicker` 與 `IvWatchlist` 的正規化寫在 **`before_save`**（驗證之後）。
若只改 `case_sensitive` 而不動這裡，使用者送 `aapl` 時驗證會比對未正規化的值
→ 驗證通過 → 存檔時 upcase → 撞上唯一索引 → 500。
**必須同時把 `before_save` 移到 `before_validation`。**
（順帶修掉一個既有小瑕疵：`IvWatchlist` 的 format 驗證目前跑在未 strip 的值上。）

- [x] B-1 四個 model 移除 `case_sensitive: false`
- [x] B-2 `TrackedTicker` / `IvWatchlist` 正規化 `before_save` → `before_validation`
- [x] B-3 補 request/model spec 釘住「小寫輸入不會產生重複列」

---

## C. Model 加 presence 驗證（6 項 NullConstraintChecker）

`UserActivity.kind`、`SkewRankIntraday.ticker/snapshot_time`、
`SkewRankDaily.ticker/snapshot_date`、`OptionSnapshot.snapped_at`

DB 已是 NOT NULL 但 model 沒驗證 → 目前會拋原始 PG 例外而非驗證錯誤。

與 A-1 的差別：**presence 驗證不產生額外查詢**（uniqueness 每次存檔要多一次 SELECT）。
即使部分寫入路徑走 upsert 不會觸發，成本仍是零，且能表達意圖。

- [x] C-1 六個欄位加 `presence: true`

---

## D. Migration 1：刪 7 個冗餘索引

已用 `pg_indexes` 逐一驗證：**7 個全部是真的 leftmost-prefix 重複，沒有 partial index**
（工具在有 `WHERE` 條件時會誤判，這次沒有這個問題）。

| 刪除 | 被誰涵蓋 |
|---|---|
| `index_watchlist_items_on_user_id` | `..._on_user_id_and_symbol` |
| `index_user_activities_on_user_id` | `..._on_user_id_and_kind_and_started_at` |
| `index_ownership_holders_on_ownership_snapshot_id` | `..._and_name` |
| `index_options_flow_trades_on_symbol_and_snapshot_date` | `idx_oft_directional` |
| `index_option_snapshots_on_tracked_ticker_id` | `idx_option_snapshots_hourly` |
| `index_margin_positions_on_status` | `..._on_status_and_opened_on` |
| `index_iv_watchlists_on_user_id` | `..._on_user_id_and_symbol` |

- [x] D-1 migration（含正確的 `down`，逐一重建）

---

## E. Migration 2：3 個 NOT NULL + 1 個 boolean

`price_alerts.target_price`、`iv_queries.ticker`、`iv_queries.option_type`、
`iv_queries.low_iv_signal`（boolean 補 NOT NULL + default false）

**已驗證現有資料 NULL 筆數皆為 0**（price_alerts 3 筆、iv_queries 20 筆）。

- [x] E-1 migration

---

## F. Migration 3：7 個 CHECK constraint

`price_alerts.target_price > 0`、`margin_positions.buy_price/shares > 0`、
`margin_positions.sell_price > 0 OR NULL`、
`portfolios.shares/unit_cost > 0`、`portfolios.sell_price > 0 OR NULL`

**已驗證現有資料違反筆數皆為 0**（margin_positions 與 portfolios 目前都是 0 筆）。

- [x] F-1 migration

---

## 執行順序與安全措施

1. [ ] **先備份資料庫**（dev/prod 共用 `fairprice_production`）並驗證備份檔完整
       ——不能只驗非空，要驗 gzip 結尾標記（見 memory `feedback_backup_validation`）
2. [ ] B / C（純 model 改動，零 DB 風險）→ 跑測試
3. [ ] D / E / F（三支 migration）→ 每支都要能 `db:rollback`
       ——memory `feedback_migration_rollback_risk`：down 失敗可能連鎖回滾前一個 migration
4. [ ] 重新跑 `bin/audit schema` 確認只剩 A 段那 8 項
5. [ ] `bin/audit all` 全綠
6. [ ] 需要重啟 `fairprice-rails`（schema 變更）——**先徵求同意**

## 風險

- `option_snapshots` 有 **810,382 筆**，刪索引時會取得短暫 ACCESS EXCLUSIVE 鎖。
  DROP INDEX 只動 catalog 與檔案，實際是毫秒級；但若當下有爬蟲在寫入會被擋一下。
- 其餘表都很小（price_alerts 3、iv_queries 20、margin_positions 0、portfolios 0）。

---

# Review（2026-08-30 完成）

## 結果：40 → 0，`bin/audit schema` exit 0

| 段落 | 項數 | 實際做了什麼 |
|---|---|---|
| B | 8 | 四個 model 移除 `case_sensitive: false`；`TrackedTicker` / `IvWatchlist` 的正規化從 `before_save` 移到 `before_validation` |
| C | 6 | 六個欄位加 `presence: true` |
| D | 7 | migration 刪 7 個冗餘索引 |
| E | 4 | migration 加 3 個 NOT NULL + 1 個 boolean NOT NULL/default |
| F | 7 | migration 加 7 個 CHECK constraint |
| A | 8 | `.database_consistency.yml` 逐項忽略並註明理由 |

## 驗證

- 三支 migration 的 `down` **全部實測往返過**（索引 7 → 0 → 7 → 0）
- 新增 9 個測試釘住正規化順序，**反向驗證過**：改回 `before_save` 立刻紅
- RSpec **712 examples / 0 failures**（原 703）
- `bin/audit all` exit 0
- 備份已建立並驗證完整（21MB、`dump complete` 標記、`option_snapshots` 810,382 筆對得上）

## 與計畫的差異

`bin/audit schema` 從「報告用」升格為**閘門**，`config/ci.rb` 同步加上該步驟。
原計畫沒寫這條——既然歸零了，不設閘門就會慢慢漂回去。

`.database-consistency.yml` 檔名錯誤（連字號），正確是 `.database_consistency.yml`
（底線）。第一次跑出現 `No configuration files were provided` 才發現。

新增的測試原本寫成一支跨四個 model 的 `symbol_normalization_spec.rb`，
被 `RSpec/DescribeClass` 與 `RSpec/MultipleDescribes` 兩條規則夾住
（一個要類別、一個要單一 top-level）。正解是拆進各自 model 的 spec，
順帶補了原本不存在的 `iv_watchlist_spec.rb` 與 `watched_ticker_spec.rb`。

## 尚未處理

- `style-src` 的 `unsafe_inline`
- `tracked_tickers` 沒有 per-user ownership（需重新 key 81 萬筆 `option_snapshots`）
