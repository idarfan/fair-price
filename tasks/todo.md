# Phase H：intrinsic_value / extrinsic_value 衍生欄位

_最後更新：2026-07-04_

規格：`leaps-call-recommendation-spec.md` Phase H 節（2026-07-04 版，人工對照已拆 fixture/live 兩層）

- [ ] 改前截圖（UI 強制流程第 1 步）
- [ ] Migration：加 `intrinsic_value`/`extrinsic_value`（decimal 10,4，允許 null）+ up_only SQL backfill
- [ ] `LeapsOptionChainSnapshot.derived_values`：公式唯一定義（Mid 基準、option_type 分支、bid/ask/spot 缺值 → 雙欄 null）
- [ ] `persist_leaps`：每筆 row 呼叫 derived_values 存入；`leaps_scraper.py` 零改動
- [ ] `LeapsRankingService#enrich`：改讀 DB 欄位，移除排行層重複公式；新增 `extrinsic_pct = extrinsic_value / mid`（display 層，mid≤0 或缺值 → nil）
- [ ] `page_component.rb`：表格加「內在價值／外在價值／外在佔比」三欄（Spread% 之後、Time Value% 之前），nil 顯示「—」
- [ ] 單元測試：深 ITM call／OTM call／bid 或 ask null／put 分支／NVTS 2026-07-02 fixture 釘公式
- [ ] display 層測試：mid=0 或 null → 佔比 nil
- [ ] request spec：完整 HTTP 路徑驗證新欄位渲染
- [ ] `rails db:migrate` + 全套 RSpec
- [ ] rebuild CSS + E2E：NVTS 不帶 user_strike 完整查詢，新欄位全數有值
- [ ] live 層人工對照：當次抓到的 bid/ask/spot 手算兩筆 vs 頁面顯示（不得對 2026-07-02 歷史數值）
- [ ] 改後截圖比對（UI 強制流程第 3 步）
- [ ] 規格 checklist 打勾附證據、commit、Obsidian 日誌

---

## LEAPS Delta 修正 — 已結案 ✅（2026-07-02）

截圖：`leaps-nok-delta-verify.png`、`leaps-klac-partial-error.png`；詳見 git log 與規格第 3 節。
