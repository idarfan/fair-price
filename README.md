# FairPrice

### 2026-08-29（六）— 升 vite 8、解開兩個相依衝突、補上前端單元測試

> **歷史說明**：這一輪同樣被自動提交 hook 拆成兩筆並已推送
> （`567f579` json 測試＋vitest 設定、`a18c5ea` 升 vite 8＋dom 測試）。
> 禁止 force push，說明補在這裡。

**兩個先前就存在的相依衝突**

`npm install` 一直裝不了任何新套件，原因是兩組 peer dependency 互斥：

```
@vitejs/plugin-react@6.0.1        要 vite@^8.0.0，專案卻釘 vite@^6.4.1
eslint-plugin-react-hooks@7.0.1   peer 只到 eslint@^9，專案已裝 eslint@10.2.0
```

兩者都是先前用 `--force` 之類硬裝起來的。升級前先確認所有 vite 消費端都接受
`^8`（`vite-plugin-ruby >=5.0.0`、`@storybook/react-vite` 與 `vitest@4.1.1`
都列了 `^8`），才動手。

| 套件 | 前 | 後 |
|---|---|---|
| `vite` | 6.4.1 | **8.2.2** |
| `eslint-plugin-react-hooks` | 7.0.1 | **7.1.1** |
| `happy-dom` | 未安裝 | **20.11.15** |

**production build 從約 10 秒降到 1.80 秒**，`react-resizable-panels` 的
`"use client"` 警告也消失。

**剩一個不影響 Rails 的 peer 不符**：`@joshwooding/vite-plugin-react-docgen-typescript@0.6.4`
（`@storybook/react-vite` 的相依）只支援到 vite 7。**只影響 Storybook**，
Rails 建置與測試都不碰它——跑 `npx chromatic` 前要留意。

**前端單元測試（28 個）**

之前說「這專案沒有前端測試框架」是錯的——`vitest@4.1.1` 早就裝好了，缺的是
DOM 環境（被上面的衝突擋住）。

| 檔案 | 測試數 | 重點 |
|---|---:|---|
| `shared/json.test.ts` | 17 | 把 `num()`（嚴格）與 `numeric()`（parseFloat 語意）的差別釘死——那正是 Skew Rank 回歸的根因 |
| `shared/dom.test.ts` | 11 | 釘住「取不到就安靜回退」的新語意（型別化前那些寫法會拋 TypeError）|

新增 `vitest.config.ts`（獨立於 `vite.config.ts`，不載入 `vite-plugin-ruby`）。
`package.json` 加 `test` / `test:watch`；`check` 改成
`tsc --noEmit && eslint . && vitest run`；`lint` 從已失效的 `--ext` 改成 `eslint .`。

**兩支測試都驗證過是有效防護**：把 `numeric()` 改回嚴格 → 3 個失敗；拿掉
`closestFrom` 的 `instanceof` 保護 → 1 個失敗。

**順帶把 `portfolioHoldings` 補驗完**

`/portfolio` 無持股資料，改用元件真實標記建合成 DOM、攔截 `/portfolio/quotes`
回 Finnhub 真實形狀（實測 `c`/`d`/`dp` 都是 `Float`，所以嚴格的 `num()` 在那裡
是對的）。六個報價欄位與手算逐項相符（市值 $3,197.00、損益 +$1,697.00、
損益率 +113.13%），雙向試算 160.00 / 50.00 也對。未動任何真實資料。

**驗證**

`npm run check` 全綠、RSpec 665/0、RuboCop 無 offense。vite 8 換掉所有 chunk
hash，重啟後逐頁重驗 `/iv_analysis`、`/watchlist`、`/technical_dashboard`，
console 零錯誤。

### 2026-08-29（五）— behaviors 全面型別化：765 個 strict error → 0

30 支 behaviors、共用模組與 entrypoints 全部從 `.js` 轉成 `.ts`。
`tsconfig.json` 的 `allowJs` / `checkJs` 已移除——**現在每一支前端程式碼都在
strict 型別檢查之下，沒有例外**。

> **歷史說明**：這一輪被自動提交 hook 拆成四筆 `chore: 自動提交` 且已推送
> （`5272f58` 基礎建設＋前 16 檔、`6772c7d` 中段 8 檔、`47acfd7` 最後 3 檔＋
> tsconfig 收尾、`9efc16e` `numeric()` 回歸修正）。因為禁止 force push，
> 歷史保持原樣，說明補在這裡。

**新增的基礎建設**

| 檔案 | 作用 |
|---|---|
| `types/globals.d.ts` | CDN 全域：`Chart` / `Sortable` / `NProgress` / `htmlToImage` / `jspdf` / `window.driver` / `ttsSpeak` / `switchDashMode` |
| `behaviors/shared/dom.ts` | `closestFrom` / `valueOf` / `csrfToken` |
| `behaviors/shared/json.ts` | fetch 回應收窄：`isRecord` / `str` / `num` / `numeric` / `arr` / `firstString` |

**零 `as`、零 `!`**

Global rules 要求 API 回應用 Zod 驗證、禁 `as`，但本專案 `npm install` 卡在
vite 的 peer dependency 衝突，Zod 裝不了。改用手寫 type predicate，整批轉換
**沒有任何 `as` 強轉，也沒有任何 `!` 非空斷言**（narrowing 在巢狀 function
declaration 裡會失效，一律改用明確型別的 const）。

**一個型別化造成的回歸（已修）**

Rails 把 BigDecimal 序列化成**字串**——`/api/iv_analysis/watchlist` 回的是
`skew_rank: "78.87"`、`strike: "100.0"`。原碼 `parseFloat` 吃得下，改成嚴格的
`num()`（`typeof === "number"`）之後整批被丟掉：Skew Rank 三張卡全變「—」、
摘要計數 3/0/0 變 0/0/0、觀察清單的履約價欄消失。

修法是新增 `numeric()`（parseFloat 語意），`ivAnalysis` 30 處改用。
**刻意不放寬 `num()`**：價差頁的 `fmt()` 原本就用 `typeof === 'number'` 判斷，
字串本來就顯示「—」，一起放寬會改壞那邊。

**保護機制：字面值比對**

型別化不該改動任何數值。`literal_check.py` 每批轉完就跟 `77c504f` 的原檔比對
數值與字串的多重集合。它抓到一次真錯：`ivEducationChart` 的 `normCDF` 常數被我
打成 `0.3989422804`（1/√(2π) 的真值），原碼是 `0.3989422820`。肉眼與測試都
抓不到。**30 支最終全部「數值零差異」。**

需要解釋的差異逐一程式化驗證：`techDashOptionsCharts` 的 4 份 tooltip CSS、
`momentumAnalysisPanel` 的 1309 字元 PDF CSS、`ivEducationChainTooltip` 的
177 條中文教學文案，都確認逐字相同。

**兩個靜態檢查抓不到、會炸站的問題**

- `entrypoints/application.js` → `.ts` 後 `vite_javascript_tag 'application'`
  解析失敗（實測 `ViteRuby.instance.manifest.path_for` 拋錯），layout 已改用
  `vite_typescript_tag 'application.ts'`
- `window.mountTechChart` 在 `technicals.tsx` 已宣告且簽名不同，重複宣告觸發
  TS2717，移除我的版本以實作端為準

**驗證**

`tsc --noEmit` 0 error、`eslint .` 0 error（warning 10 → 2）、RSpec 665/0、
RuboCop 無 offense。12 個頁面在瀏覽器逐頁實測，`/bpus` 與 `/bcvs` 走完整
Barchart 抓取流程，數字與型別化前逐項相同（bcvs K2 $327.50、淨成本 $6.40）。

**未驗到**：`portfolioHoldings` 的拖曳排序與獲利↔賣價雙向試算——`/portfolio`
目前無持股資料，那些路徑進不去。

### 2026-08-29（四）— M-6：兩支價差試算頁抽出共用模組

`bull_put_spreads` 與 `bull_call_spreads` 的重複程式碼在 H-3 之後變成兩支並排的
`.js`，這次把真正重複的部分抽掉。實測兩檔完全相同的行有 101 行（占 put 檔 22%），
其餘差異幾乎只是 DOM id 前綴（`bpus-` / `bcvs-`）。

**新增兩個共用模組**

- `behaviors/shared/spreadHelpers.js` —— `createSpreadHelpers({ prefix, statusPath })`
  回傳 `csrf` / `fmt` / `fmtLots` / `currentLots` / `showProgress` / `pollJob`
- `behaviors/shared/colTooltip.js` —— `initColTooltip({ prefix, colExplain })`，
  回傳 `{ drv, hide }` 供呼叫端擴充

Vite 確認兩對頁面各自 import 同一份 chunk（`_spreadHelpers`、`_colTooltip`），
不是各打包一份。

| 檔案 | 前 | 後 |
|---|---:|---:|
| `bullPutSpreads.js` | 503 | 471 |
| `bullCallSpreads.js` | 434 | 403 |
| `bullPutTooltips.js` | 57 | **19** |
| `bullCallTooltips.js` | 73 | 57 |

**三個實作決定**

1. **tip 容器 id 用 prefix 參數化，不改名**——`application.css` 對
   `#bpus-col-tip` 與 `#bcvs-col-tip` 各有一份樣式，`.tip-t` 字級還不同
   （13px vs 22px）。`prefix + '-col-tip'` 產生完全相同的 id，CSS 一行不用改。
2. **`pollJob` 的 statusPath 改成建立時綁定**——原本 put 版讀 `CFG.routes.status`、
   call 版當第二個參數傳，統一後 call 端兩處呼叫各少一個參數。
3. **bcvs 的 9 步導覽改成獨立 click listener**——原本接在欄位 popover 的 `return`
   之後。共用核心只處理 `[data-tip-key]`、這裡只處理 `#bcvs-tour-btn`，同一次點擊
   不會同時命中（已實測：點欄位只開 1 of 1，不會誤觸 1 of 9）。

順帶清掉 bcvs 版 `fmt` / `fmtLots` 多寫的 `n !== null`——前面已有
`typeof n === 'number'`，而 `typeof null === 'object'`，那個檢查永遠不成立。

**驗證**

665 examples / 0 failures、RuboCop 通過、`tsc` 0 error、`eslint .` 0 error。

兩頁在瀏覽器各跑完整流程，數字與重構前逐項相同：

| | `/bpus` | `/bcvs` |
|---|---|---|
| 選擇權鏈 | 108 列 | 105 列 |
| 試算 | 淨權利金 $55.00、ROC 5.8% | K2 $327.50、淨成本 $6.40 |
| 口數 3 | `$55.00 × 3 = $165.00` | `$640.00 × 3 = $1920.00` |
| tooltip | 13px ✅ | 22px ✅ |
| 其他 | — | 修復模式 $-530/-60/+720、導覽 1 of 9 |

console 零錯誤零警告。

### 2026-08-29（三）— 全面清掃「原始碼裡有、執行時到不了」的死碼

把當天稍早發現的兩類問題掃過整個 codebase：預設關閉但沒人開啟的可選功能，
以及被上游 constraint 蓋掉的驗證。

**刪掉 3 個正式碼零呼叫端的元件（171 行）**

| 死元件 | 被什麼取代 |
|---|---|
| `DailyMomentum::NewsCardComponent` | `NewsTabPanelComponent` + `momentumNewsTabs.js` |
| `DailyMomentum::WatchlistTableComponent` | `WatchlistManagerComponent` |
| `FairValue::PageLayoutComponent` | `app/views/layouts/application.html.erb` |

`PageLayoutComponent` 在 `log/development.log` 裡留有 `undefined method
'stylesheet_link_tag'` 的例外記錄——它不只沒人用，最後一次被渲染時就已經壞了。
三個都只剩 Lookbook preview 在引用，preview 一併刪除。

**清掉 4 處死碼／no-op**

- `bullPutSpreads.js` `hideProgress()`——沒有任何呼叫處。`showProgress()` 之後
  每條路徑都是整頁導覽，頁面直接被銷毀，所以本來就不需要收起進度條
- `bullPutSpreads.js` 重複的 `runCalculate()`——函式宣告會提升，後面同名那份
  永遠覆蓋前面這份（少了 `lastCalcResult` 與追蹤事件），從未執行過
- `bullCallSpreads.js` `k2Bid`——先用 `tab.k2 - tab.breakeven + k1` 算一次，
  下面必定覆寫，算出來的值從來沒被讀過
- `bullCallSpreads.js` `fillRepairFromTab()`——寫進 `basisInput` 的兩個 data
  attribute 全專案沒人讀（其中一行的三元運算子兩邊還都是空字串），
  `runRepairIfReady()` 是從 `lastTabs[activeTab]` 與鏈上那一列取值。移除後整個
  包裝函式只剩一行轉呼叫且參數已無用，直接內聯

**ESLint 閘門修好**

`npx eslint .` 原本會吐出兩萬多則來自 `storybook-static/`、`vendor/assets/`、
`venv/` 的雜訊——等於整個 lint 閘門沒人跑得動（先前回報的「0 error」是限定範圍
跑出來的）。補上建置產物的 ignores，再為 `app/assets/javascripts/**`（Wave 1 拆出
的 LEAPS 靜態檔）與 `.cjs` 補上正確的 globals，剩下的 12 個 error 逐一處理完。

現在 `npx eslint .` 全庫 **0 error**，10 個 warning 是逐字搬移的 ES5 慣用寫法
（`no-redeclare`、三元運算子當敘述）與兩處刻意的 `set-state-in-effect`，留給
型別化那一輪。

**沒有動的**

`ValuationTableComponent` 的 `show_formulas` 也是永遠 false，但呼叫端
（`valuations/show.html.erb:39`）是**明確傳 `false`**，屬於刻意關閉而非疏漏，
跟 `alert-dismiss` 那種沒人想過的情況不同，留待產品決定。

**驗證**

665 examples / 0 failures、RuboCop 通過、`tsc --noEmit` 0 error、`eslint .` 0 error。
瀏覽器實測受影響的兩支：`/bpus` 走完到 108 列選擇權鏈 → 選腳 → 試算（$55.00
淨權利金）→ 改口數重繪（`$55.00 × 3 = $165.00`，證明 `lastCalcResult` 有寫入）；
`/bcvs` 走完到 105 列 → K1 推薦三分頁 → 修復模式試算（≤K1 $-530.00／口、
中間情境 $-60.00／口、≥K2 鎖定 $720.00／口）。

### 2026-08-29（二）— 兩處「原始碼裡有、執行時到不了」的死碼修好

同日稍早的瀏覽器驗證挖出兩個同一類問題：程式碼寫了、測試也掃得到，但實際跑起來
永遠不會執行。

**1. 提示訊息的關閉按鈕（`alert-dismiss`）**

`FairValue::AlertComponent` 的 `dismissible` 預設 `false`，而全部 5 個呼叫端都沒有
傳 `true`（只有 Lookbook preview 會），所以那顆 ✕ 在正式站從來不會渲染。

預設值改成 `true`——現有用法全是 flash 提示，本來就該能關掉。要保留不可關閉的
用法仍可明確傳 `dismissible: false`。

**2. `ValuationsController#validate_ticker`**

HTML 路由的 `TICKER_CONSTRAINT` 與 controller 裡的檢查等價，不合法代號在路由層
就被擋成 404，那段「無效的股票代號」的友善提示永遠進不去。

但搜尋列（`tickerSearch.ts`）只檢查非空就直接 `window.location.href = ...`，所以
使用者打「台積電」或帶空白的代號，看到的是原始 404 頁。

HTML 路由改成收下整個 segment、由 controller 驗證並導回首頁。兩個實測確認的細節：

- `format: false` 是必要的——放寬 constraint 之後 Rails 會把 `BRK.B` 的 `.B` 當成
  格式後綴切掉（原本的 constraint 剛好含 `.` 才沒發生）
- API 端（`api/v1/valuations`）維持嚴格 constraint：對 API 而言 404 才是對的回應

**新增測試**

`behavior_registry_spec` 掃原始碼，看到 `behavior: "alert-dismiss"` 就算通過，
但那證明的是「原始碼裡有」，不是「執行時會渲染」。新增的兩支 request spec 補的
就是那一層：

- `spec/requests/alert_dismiss_spec.rb`（4）
- `spec/requests/valuation_ticker_validation_spec.rb`（8）

**涉及檔案**

- `app/components/fair_value/alert_component.rb`
- `app/controllers/valuations_controller.rb`
- `config/routes.rb`
- `test/components/previews/fair_value/alert_component_preview.rb`

### 2026-08-29 — H-3 瀏覽器實測 30 個 behavior，順手修掉字級還原白名單漂移

H-3 搬遷完成當下，30 個 behavior 裡只有 4 個（登入頁上的）驗過。這次登入後在真實
瀏覽器把 12 個頁面全部走完，確認每個 chunk 都以 200 載入、CSP 沒擋下任何 script，
並對互動類的實際操作過（tooltip hover、分頁切換、拖曳排序掛載、刪除確認攔截、
Chart.js 建立、bpus/bcvs 完整跑到選擇權鏈 108 列）。

`alert-dismiss` 是唯一無法在正式站觸發的——所有呼叫端都沒傳 `dismissible: true`
（只有 Lookbook preview 會），它在正式站從來不會渲染。這是搬遷前就存在的死路，
改用直接載入 chunk + 重建元件 DOM 形狀的方式驗證模組本身。

**修正：字級選 19–22px 換頁後被打回預設**

`FontSizeControlsComponent::SIZES` 給的是 18–22px，但 layout 裡「繪製前還原字級」
的白名單寫死 `['14','15','16','17','18']`，交集只有 `18`。`git show cdd4964^`
確認搬遷前就是這樣，不是 H-3 造成的。

改成兩邊都從同一個常數推導（元件新增 `.allowed_sizes`，layout 與 behavior 都讀它，
behavior 改吃 `data-sizes`），避免兩份寫死再次漂移。

**涉及檔案**

- `app/components/fair_value/font_size_controls_component.rb`
- `app/views/layouts/application.html.erb`
- `app/frontend/behaviors/fontSizeControls.js`

### 2026-08-28 — H-3 完成：內嵌 JavaScript 全數搬進 Vite，CSP 拿掉 `unsafe_inline`

接續同日的 Wave 1。Wave 2 處理有 Ruby 插值的 6 個元件（707 行，改用 data attribute
傳值），Wave 3 處理 `bull_put_spreads` / `bull_call_spreads`（1,038 行、35 處插值，
路由與頁面狀態改用單一 `data-config` JSON——`dataset` 只能給字串，會把 `nil` 變成
空字串而改變 truthiness，用 JSON 才能保留 `null` 與數值型別）。

最後把 layout 自己的 3 段與 `stock_alerts/index.html.erb`、`alert_component.rb`
也一併清掉。

**成果**

| | 前 | 後 |
|---|---|---|
| 元件內嵌 JS | 3,933 行 / 18 個元件 | **0** |
| 全站 inline `<script>` | 22 段 | **1 段**（帶 CSP nonce） |
| CSP `script-src` | `'self' 'unsafe-inline' cdn` | **`'self' cdn 'nonce-…'`** |
| `npx tsc --noEmit` | 跑不動（沒有 tsconfig） | **0 error** |
| ESLint | 22 problems（20 個是假陽性） | **0 error** |

唯一保留的 inline script 是還原字級那段——它必須在瀏覽器繪製前執行，不能等
Vite module 的 defer，否則每次換頁都會看到字級閃動。改用
`javascript_tag nonce: true` + `content_security_policy_nonce_generator`
放行（專案沒有 fragment cache，不會有快取到舊 nonce 的問題；日後要加 fragment
cache 前務必重新確認這點）。

`style-src` 仍保留 `unsafe_inline`：Phlex 與 Tailwind 大量使用 inline style
屬性與 `<style>` 區塊，那是另一件事。

**ESLint 上線後在搬遷的程式碼裡抓到的**（都是搬遷前就存在的）：
`bullPutSpreads.js` 的 `hideProgress()` 全專案沒有任何呼叫處；
`bullCallSpreads.js` 的 `k2Bid`（L378）下一個分支必定覆寫，計算結果永遠沒被讀。
刻意不在搬遷這一輪動它們（優先保證行為完全不變），已在 `eslint.config.js` 註記。

**瀏覽器實測**（`/login`，唯一不需登入的頁面）：CSP header 已無 `unsafe-inline`、
inline script 帶 nonce 且正常執行、`releaseNotes` 與 `appSwitcher` 兩個搬遷後的
模組點擊開關都正常運作、console 零錯誤零警告。

**尚未驗證**：其餘 26 個 behavior 分布在登入閘門後的頁面，尚未做視覺與互動驗證。

**後續**：`behaviors/*.js` 型別化成 `.ts`（逐字搬進 strict TS 光 `ivAnalysis`
一支就有 209 個錯誤）；`bull_put` / `bull_call` 兩支之間的大量重複（稽核 M-6）
現在變成兩個並排的 `.js`，可以直接 diff 抽共用，比在 Ruby heredoc 裡容易得多。

### 2026-08-28 — H-3 Wave 1：內嵌 JavaScript 搬進 Vite，並補上 TypeScript / ESLint 把關

**前置：把前端的檢查機制建起來**

- 新增 `tsconfig.json`（`strict: true`）。原本專案沒有 tsconfig，`npx tsc --noEmit`
  根本跑不動。修掉既有的 9 個型別錯誤後，型別檢查現在是 **0 error** 的真實 gate。
  `noUncheckedIndexedAccess` 暫時關閉——開啟後還有約 30 個「可能是 undefined」要處理，
  集中在 `OptionsChainTable.tsx` 與 `payoff.ts`，留給獨立的一輪
- `eslint.config.js` 補上瀏覽器全域宣告。原本沒有宣告，導致 `document` / `window` /
  `fetch` 一律被 `no-undef` 判成錯誤——**20 個假陽性，等於 ESLint 對前端形同虛設**。
  修好之後又修掉 4 個真錯誤（2 個未使用的 catch 參數、2 個 `any`），
  現在是 **0 error / 2 warning**
- `package.json` 新增 `npm run typecheck` 與 `npm run check`

**搬遷**

新增 `app/frontend/entrypoints/behaviors.ts`：掃描 `[data-behavior]`，用動態 import
只載入該頁真正需要的模組，Vite 自動 code-split。Phlex 元件只留一行掛載標記
`div(data: { behavior: "..." })`，新增行為不需要動 layout。

搬遷 10 個元件、12 段、**2,188 行**（占全部內嵌 JS 的 56%）：

| 元件 | 檔案行數 |
|---|---|
| `iv_analysis/page_component.rb` | 751 → **30** |
| `iv_analysis/education_component.rb` | 1348 → 884 |
| `daily_momentum/analysis_panel_component.rb` | 277 → 49 |
| `iv_watchlists/index_view.rb` | 263 → 46 |
| `portfolio/holding_list_component.rb` | 326 → 170 |
| `shared/ownership_panel_component.rb` | 213 → 72 |
| `daily_momentum/news_tab_panel_component.rb` | 184 → 49 |
| `daily_momentum/watchlist_manager_component.rb` | 149 → 77 |
| `stock_alert/alert_list_component.rb` | 177 → 143 |
| `fair_value/search_bar_component.rb` | 147 → 127 |

擷取用 **Ruby 自己求值**而不是純文字複製：unquoted heredoc（`<<~JS`）Ruby 會先處理
反斜線跳脫，直接複製會讓 `'\n'` 從換行變成 literal `\n`、`/\d+/` 變成 `/\\d+/`。
實際有 14 行受影響。

最小的兩支（`tickerSearch` / `alertList`）直接改寫成 strict TypeScript；其餘 10 段
逐字搬成 `.js`（`allowJs: true, checkJs: false`，誠實標示未型別化），
優先保證行為完全不變。逐字搬進 strict TS 光 `ivAnalysis` 一支就有 209 個型別錯誤，
全部型別化是獨立的一輪工作。

**ESLint 上線後立刻抓到的東西**：`window.switchDashMode` 被以 bare call 呼叫
（語意正確但靜態分析看不到，已改成 `window.` 前綴）、`Option` / `Audio` /
`EventSource` 等未宣告全域、6 處 `var` 重複宣告。

新增 `spec/frontend/behavior_registry_spec.rb`（5 個案例）把元件與模組之間那條
只剩字串的連結釘住：未註冊的 marker、註冊了卻沒有檔案、模組沒 export `init`、
沒人使用的孤兒、以及「已搬遷的元件不可以又把 JS 塞回 heredoc」。

**驗收**：RSpec 653 examples / 0 failures、`tsc --noEmit` 0 error、
ESLint 0 error、RuboCop 無 offense、12 個 behavior chunk 都有產出 source map。

**剩餘**：8 個元件、1,745 行內嵌 JS（`bull_put_spreads` 552、`bull_call_spreads` 486、
`technical_dashboard` 458 是大宗，都有較多 Ruby 插值），以及 layout 自己的
inline `<script>`。要拿掉 CSP 的 `unsafe_inline` 得等這些全部清完。

### 2026-08-28 — 觀察清單加上使用者歸屬（C-2 第二階段）

稽核 C-2 原本只做了 `margin_positions` / `portfolios` / `price_alerts`，
剩下三張表被擱置的原因是**它們都有排程在讀，而排程沒有 `current_user`**：

| 表 | 誰在讀 | 頻率 |
|---|---|---|
| `tracked_tickers` | systemd `options-collector.timer` + `options-intraday.timer` → `options_collector.py:138` | 每日 EOD + 每 30 分 |
| `watchlist_items` | pm2 `ouou-pre-market` → `OuouPreMarketService#watchlist_symbols` | 每日盤前 Telegram |
| `iv_watchlists` | pm2 `iv-skew-snapshot` / `iv-skew-intraday` → `lib/tasks/iv.rake:25,51`、`backfill_iv_skew.py:168` | 每日 + 盤中 |

能不能分人，取決於**蒐集結果怎麼 key**：`iv_daily_snapshots` / `skew_rank_daily` /
`skew_rank_intradays` 都是 ticker-keyed，一個代號只會有一份，多人追蹤不會重複抓；
`option_snapshots` 則是綁 `tracked_ticker_id` 且有 80 萬列。

- `watchlist_items`、`iv_watchlists` 加 `user_id`，既有資料歸給 admin。
  `symbol` 的唯一索引從「全站唯一」改成 `[user_id, symbol]`，
  否則第二個使用者連加入同一個代號都會被擋
- 排程改取**所有使用者的聯集**（`WatchlistItem.ordered.pluck(:symbol).uniq`、
  `IvWatchlist.active.pluck(:symbol).uniq`）。既有資料全歸 admin，
  所以聯集 == 目前的集合，排程行為完全不變（實測盤前 23 個代號、skew 7 個代號，與修改前一致）
- `db/seeds.rb` 改成掛在 admin 底下；沒有任何使用者時跳過而不是炸掉
- `tracked_tickers` 維持共用，改為**只有 admin 能寫入**（`create` / `update` /
  `destroy` / `collect`），避免其他帳號刪代號時連帶 `dependent: :destroy`
  掉整段歷史快照；讀取仍開放給所有登入者
- 新增 `spec/requests/watchlist_isolation_spec.rb`：跨使用者看不到／刪不掉、
  排程取聯集、tracked_tickers 的 admin 限制，共 9 個案例

**仍未處理**：`tracked_tickers` 要真正分人，得先把 `option_snapshots` 從
`tracked_ticker_id` 改成 symbol-keyed 再拆出個人訂閱表——那是 80 萬列的遷移，另開。

**驗收**：RSpec 648 examples / 0 failures、Brakeman 0 warnings、RuboCop 349 檔無 offense；
正式資料完好（WatchlistItem 23、IvWatchlist 6、OptionSnapshot 801,222）。

### 2026-08-28 — 正式資料庫更名，並補回 Rails 破壞性指令的保險

接續同日的稽核修正。稽核時發現「測試環境連到正式資料庫」，堵住測試那一側之後
追下去，根因是**正式資料住在一個叫 `fairprice_development` 的資料庫裡**，
`fairprice_production` 根本不存在。

連帶造成 Rails 最重要的一道保險失效：`protected_environments` 檢查的是
**資料庫裡存的環境標記**，而那個標記是 `development`——
`rails db:drop` / `db:reset` / `db:schema:load` 打在正式資料上，一句都不會攔。
（先前 `db:test:prepare` 之所以被擋，撞到的是另一道 `EnvironmentMismatchError`，
是名字對不上的運氣，不是保護。）

- `ALTER DATABASE fairprice_development RENAME TO fairprice_production`，
  `ar_internal_metadata.environment` 改為 `production`
- `.env` 的 `DATABASE_URL`、`scripts/backup_db.sh`、`install.sh`、
  `python/fix_missing_prices.py`、`scripts/options_collector.py` 一併更新
- `config/database.yml` 的 `development` 也指向 `fairprice_production`
  ——這台機器上本來就沒有獨立的開發資料庫，明寫出來比讓它看起來像分開的好
- `config/application.rb` 設 `protected_environments = %w[production development]`：
  兩個環境共用同一個庫時，那個標記會被 `db:migrate` 寫成當下的 `RAILS_ENV`，
  只保護 `production` 的話，隨手跑一次不帶 `RAILS_ENV` 的 `db:migrate`
  就會把標記翻回 `development`，保險靜靜失效。兩個名字都保護才擋得住

**驗收**：`rails db:drop`（development 模式）已被 `ProtectedEnvironmentError` 擋下；
`db:test:prepare` 與備份腳本照常運作；RSpec 638 examples / 0 failures；
資料完好（User 5、OptionSnapshot 796,822）；公網 UI 302、API 未登入 401。

### 2026-08-28 — 稽核修正：關閉 `/api/*` 公網匿名存取，個人資料加上使用者歸屬

以 `RAILS_AUDIT_REPORT.md` 的稽核結果為依據執行修正。

**Critical**

- **`/api/*` 整個命名空間過去不需要登入，且 CSRF 關閉**。`ApplicationController` 的
  `GATE_EXEMPT_PREFIXES` 含 `/api`，導致 Google OAuth + 強制 TOTP + 雙重逾時那一整套
  防護在 API 上完全不生效。實測 `https://fairprice-ohmy.com/api/v1/tracked_tickers`
  從公開網際網路匿名回 200 + 真實資料，`DELETE /api/v1/margin_positions/:id` 等
  破壞性端點同樣匿名可打。現在 API 與 UI 共用同一份閘門，只是把 302 導頁換成
  401/403 JSON（新增 `JsonAuthGate` concern）；CSRF 由 `null_session` 改為 `exception`
- 前綴白名單由 `start_with?` 改成 anchored regex，避免 `/logout_backdoor` 這類路徑誤入白名單
- **個人性資料加上 `user_id`**（`margin_positions` / `portfolios` / `price_alerts`），
  既有資料歸給 admin。目前有 5 個 enabled 帳號，這些表過去是全站共用的；最嚴重的是
  `PortfoliosController#ocr_import` 裡的 `Portfolio.delete_all`——任何使用者匯入截圖
  就會清空所有人的持股。`TrackedTicker` / `WatchlistItem` / `IvWatchlist` 刻意不加歸屬，
  它們是共用的市場資料與排程來源
- **測試環境連到正式資料庫**：`.env` 的 `DATABASE_URL` 寫死指向 `fairprice_development`，
  而 dotenv-rails 在 test 環境同樣會載入 `.env`，整套 RSpec 一直跑在正式資料上
  （`db:test:prepare` 曾試圖 purge 正式資料庫，被 Rails protected environments 擋下）。
  `config/database.yml` 的 test 區塊改為明確指定 `url:` 壓過 `DATABASE_URL`。
  隔離後原本 13 個失敗中有 8 個消失——那些是正式資料污染造成的假結果

**High**

- `tracked_tickers#collect` 從 request 內同步跑 Python 子行程改成 `CollectOptionSnapshotsJob`
  背景執行，加上 5 分鐘硬性 timeout 與子行程強制回收。過去無 timeout，`RAILS_MAX_THREADS`
  只有 5，五個請求就能讓整站沒有回應。前端改為輪詢 `collect_status`
- `config.force_ssl` 啟用（Secure cookie）。刻意不開 `assume_ssl`——它會無條件把每個請求
  標記成 https，讓本機 `http://localhost:3003` 的 redirect 也變成 https。改為依
  cloudflared 送來的 `X-Forwarded-Proto` 判斷，公網 https、本機 http 兩邊都正確。
  HSTS 交給 Cloudflare 端設定，避免把 localhost 鎖成 https
- `TrackedTicker#last_snapshot_date` 的 N+1：兩個 controller 各自維護一份重複的
  serializer 且都逐筆查 `MAX(snapshot_date)`（`option_snapshots` 有 79 萬列）。
  抽成 `TrackedTickerSerializer`，改用單次 group query（實測 3 個代號由 3 次降為 1 次）
- `api/iv_analysis#watchlist` 每個代號開 3 條 thread 且無上限，改為比照
  `MomentumReportService` 的分批寫法
- `bundle update mail`（GHSA-mvxr-6m87-mv2q）

**Medium**

- 移除 `public/tech_prototype.html`——`public/` 下的檔案繞過登入閘門與瀏覽軌跡記錄
- 三處把 `e.message` 直接回傳給客戶端的地方改為 log 詳細、回籠統訊息
  （`Api::V1::Valuations#show`、`Api::V1::Options#analyze_image`、`Portfolios#ocr_import`）
- `BarchartScraperService#cdp_available?` 的裸 `rescue` 補上記錄（全專案唯一一處無記錄的）
- `TrackController#page_view` 檢查 `save` 回傳值
- `iv_queries` 補上 `[ticker, queried_at]` 索引（全專案唯一沒有任何索引的表）
- 三處前端寫入請求缺 `X-CSRF-Token` 已補齊，`csrfToken` 重複定義抽成 `app/frontend/lib/csrf.ts`

**驗收**：RSpec 638 examples / 0 failures（隔離的 test DB）、Brakeman 0 warnings、
RuboCop 339 檔無 offense、bundler-audit 無漏洞、ESLint 無新增問題。
公網實測 `/api/*` 未登入回 401。

### 2026-08-27 — 修復 playwright-chrome MCP 連不上，`@playwright/mcp` 升到 0.0.79

- `@playwright/mcp` 由 0.0.77 升到 0.0.79（local + global）
- MCP log 顯示 2026-08-07 ~ 08-27 每一次 session 都是同一則錯誤「Chrome CDP（port 9224）連不上」，並非 playwright-mcp 崩潰 —— 8/06 改連 9224 時沒有對應的 keeper，重開機後沒人拉起那個視窗。已在 `x-order-manager-systems` 補上 pm2 `chrome-cdp-keeper-9224`
- 移除重複的 MCP 定義：user scope 的 `railsMcpServer` 刪除，保留專案 scope 的 `rails-mcp-server`
- 移除已廢棄的 pm2 `cdp-relay`（Docker 端早已改用 `network_mode: host` 直連 9222）

### 2026-08-26 — 修復失效已久的排程備份，並將備份異地同步到 Windows 桌面

- pm2 `fairprice-db-backup`（每日 22:00）產出的備份長期都是 0 或 20 bytes 的無效檔。根因是 `scripts/backup_db.sh` 從未 `source .env`，`DB_PASSWORD` 永遠為空，`pg_dump` 轉為互動式索取密碼而失敗
- 次要根因：空檔檢查只有 `[[ ! -s ]]`（僅擋 0 bytes），但 `pg_dump` 失敗時 `gzip` 仍會產生 20 bytes 的有效空壓縮檔，通過檢查後冒充成功的備份
- `scripts/backup_db.sh` 重寫：加 `source .env`；`pg_dump -w` 絕不互動式問密碼；完整性驗證改為 `gzip -t` + 檢查 `PostgreSQL database dump complete` 結尾標記；`pg_isready` 重試等待 PostgreSQL 就緒；備份成功後同步一份到 Windows 桌面 `fairprice backup/`；保留策略 7 天並涵蓋 `pre_edit_*`（舊版只清 `fairprice_development_*`，是本機堆積到 1.7 GB 的原因）
- 清理空檔必須用 `find -size -1024c`（byte 單位）。`-size -1k` 以 1k 區塊計算且向上取整，20 bytes 算作 1 個區塊，永遠刪不到

### 2026-08-10 — 修正 LEAPS 推薦分析誤用「近期無成交」警示排除高 OI 候選

- `LeapsRankingService#low_vol_oi?` 的「近期無成交」其實是 Volume/OI 比值在查詢池中的後 1/3 分位（相對排名），不是字面上的零成交，OI 極高但比值偏低的合約也會被誤標
- `LeapsRecommendationService#recommend_group` 原本拿這個警示做 `reject` 排除，導致近天期推薦選中 OI 遠低於候選表榜首的合約，`build_reason` 卻寫「為此天期區間最高」，跟候選排行表對不上
- 修正：移除排除邏輯，推薦挑選純依 `liquidity_tier` + OI 排序（跟候選表邏輯一致）；警示改為對 `pick` 本身的資訊性提示，文案改為「Volume/OI 比率偏低」
- 詳見 `tasks/lessons.md` 2026-08-10 條目

### 2026-07-13 — 新增牛市差價看跌期權(三級版)試算工具

- 新增 `/bpus` 頁面：輸入代號 → 選履約日 → 從 Barchart Put 鏈選保護腳(Long Put)/CSP 腳(Short Put) → 即時算淨權利金、押金、損益平衡點、ROC、風險報酬比，並標示賠錢情境
- 新增 Python sidecar `bpus_expirations_scraper.py` / `bpus_put_chain_scraper.py`，沿用既有 CDP 9222 直連模式（未經 9223 relay）
- 新增 `BullPutSpreadCalculatorService` 純計算 service、`BullPutSpreadsController`、`BpusFetchExpirationsJob`/`BpusFetchChainJob`、`BullPutSpreads::PageComponent`
- Sidebar 最後一項加入口
- 修正過程中發現並修正兩個既有機制的相容性問題：`FetchLog::FETCH_TYPES` 白名單需同步加入新 fetch_type（否則 `log_fetch` 內部 rescue 會靜默吞掉 `RecordInvalid`）；Barchart Options 頁面帶 `view=sbs` 時會同時掛載多個 `bc-data-grid`（Call/Put/合併），不能只抓第一個 grid

### 2026-06-21 — 技術面/基本面/Options Flow 三維度判斷儀表板

- 新增 Barchart CDP scraper 三件套（, , ）
- 直接 WebSocket 連 CDP（非 Playwright），解決 Windows Chrome 背景 tab 凍結問題（Target.activateTarget）
- 新增 DB 表：, , , 
- ：依序爬取三維度資料，任一步驟 session 過期即中止
- ：三個獨立分數（技術/基本面/Options Flow），絕不合併，背離時生成警示文字
- Phlex ：深色評分卡、背離警示、5 分鐘快取
- 路由：，已加入側邊欄 🧭 三維度判斷


美股公平價值分析 + 每日動能報告工具，運行於 port 3003。

## 技術棧

- **Ruby on Rails 8.1** + Propshaft
- **Phlex 2.x** — UI 元件（禁止 ERB partial）
- **Lookbook** — 元件預覽（開發環境）
- **kramdown** — 伺服器端 Markdown 渲染
- **Tailwind CSS v4**（tailwindcss-rails gem，本地編譯）
- **Finnhub API** — 股票報價來源
- 無資料庫、無 Hotwire、無 React

## 啟動

```bash
systemctl --user restart fairprice
systemctl --user status  fairprice
journalctl --user -u fairprice -n 30
```

開發時需同步編譯 Tailwind：

```bash
bin/dev
```

或手動 rebuild：

```bash
bundle exec rails tailwindcss:build
```

## 工具路由

| 工具 | 路由 | Controller |
|------|------|------------|
| FairPrice | `/`, `/valuations/:ticker` | `ValuationsController` |
| Daily Momentum | `/momentum` | `ReportsController` |
| JSON API | `/api/v1/valuations/:ticker` | `Api::V1::ValuationsController` |
| 元件預覽 | `/lookbook` | Lookbook Engine |

## Lint

```bash
bundle exec rubocop
bundle exec rubocop -a   # 自動修正
```

---

## 變更記錄

### 2026-08-06 — LEAPS 排行移除 Delta 0.90 上限，改為 Delta>=0.60 全部列出

**動機：** 使用者查 NOK 履約價 4.5，推薦分析卻換成鄰近的 $5.00。查明是 `LeapsRankingService` 的 `DEFAULT_DELTA_MAX = 0.90` 從未被移除過——2026-07-01 那次「放寬 Delta 篩選」只調了下限（0.75→0.60），上限一直卡著。$4.5 在 2028-01-21 到期的 Delta 是 0.9008，只差 0.0008 就超過舊上限，整檔被排除候選名單。

**異動內容：**
- `app/services/leaps_ranking_service.rb`：拿掉 `DEFAULT_DELTA_MAX`，`fetch_candidates` 只用 `delta >= @delta_min` 篩選，深度價內（Delta 逼近 1）候選不再被排除
- `app/components/leaps_recommendations/page_component.rb`、`app/components/fair_value/app_switcher_component.rb`：sidebar 與頁面說明文字同步從「Delta 0.60–0.90」改成「Delta ≥ 0.60」
- `leaps-call-recommendation-spec.md`：更新規格文件所有 0.60–0.90 篩選描述為 Delta>=0.60（無上限），記錄變更日期
- `lib/barchart_scrapers/leaps_scraper.py`：更新 comment 說明 Stage 2 最終篩選同步移除上限
- `spec/services/leaps_ranking_service_spec.rb`：更新 delta filter 邊界測試

### 2026-08-05 — 全專案安全性維護：rubocop 修正、Brakeman 升級、22 個 CVE gem 升級

**動機：** CI 的 `lint` 與 `scan_ruby` job 長期處於失敗狀態（在這次修改之前就已經壞了），順手一次清乾淨，讓 CI 恢復綠燈當作日常品質關卡。

**異動內容：**
- `bundle exec rubocop -A` 修掉 29 個檔案、136 筆違規（主要是 `Layout/SpaceInsideArrayLiteralBrackets`），修正後全專案 0 offenses
- Brakeman 8.0.4 → 8.0.5；升級後掃出 5 個警告，逐項審查確認皆非真漏洞（Open3 用 argv 陣列非 shell 字串、SQL 已用 `connection.quote()`/`clamp` 防護、`send_file` 已有路徑穿越邊界檢查），寫入 `config/brakeman.ignore`
- `bundler-audit` 抓到的 22 個有已知 CVE 的 gem 全部升級：Rails 全家桶 8.1.2 → 8.1.3.1（`actionpack`/`actionview`/`activestorage`/`activesupport` 等，修 XSS 相關 CVE）、`action_text-trix`、`view_component`、`websocket-driver`、`yard`、`rack`、`nokogiri`、`puma`、`json` 等
- `~/.claude/hooks/pre-commit-rubocop.sh`（新增）：commit 前對 staged `.rb` 檔案跑 rubocop 檢查模式，補上 `post-edit-ruby.sh` 只在 Claude Code Edit/Write 時觸發的覆蓋盲區
- `~/.claude/hooks/post-edit-ruby.sh`：修正 exit code bug（`rubocop -A | head -20` 讓 `$?` 恆為 head 的結束碼，改用 `PIPESTATUS[0]`）
- `~/.claude/hooks/pre-commit-xss-scan.sh`：加上「單行 >400 字元視為 minified/vendored 略過」的過濾規則，避免誤判內建在課程 html 裡的 driver.js 等第三方套件

### 2026-08-05 — 修復 public/csp 未登入即可存取漏洞，新增全站閒置逾時機制

**動機：** 使用者反應 `https://fairprice-ohmy.com/csp/index.html` 不需登入就能看到、也不會留下瀏覽記錄。查明是 `public/csp/` 整包靜態檔案（381 個檔案，含期權小學堂工具、內部筆記、截圖、開發過程遺留的 `.claude/` 設定殘留）繞過 `enforce_auth_gate`——`ActionDispatch::Static` 直接把 `public/` 下的檔案吐給瀏覽器，根本沒進到 Rails controller，pm2 日誌顯示已有外部 IP（61.230.110.224）實際掃到並存取過。

**異動內容：**
- 期權小學堂工具本體（12 個課程 html + 5 個圖片/svg）搬到非 public 的 `private/csp_lessons/`，其餘 364 個開發過程遺留檔直接刪除
- `app/controllers/csp_lessons_controller.rb`（新增）：serve `private/csp_lessons/`，走登入驗證 + 記錄 `page_view` 瀏覽記錄
- `config/routes.rb`：新增 `get "csp/*path"`（注意 `format: false`，否則 `.html` 副檔名會被當成 format 參數吃掉導致 404）
- `app/components/fair_value/app_switcher_component.rb`：sidebar 新增「期權小學堂」入口
- `app/controllers/application_controller.rb`、`app/controllers/sessions_controller.rb`：新增全站閒置 2 小時強制重新登入機制（`enforce_idle_timeout`），`mr.idarfan@gmail.com` 例外不受限
- `lib/barchart_scrapers/leaps_scraper.py`：`main()` 例外不再印出裸 Python traceback，改為結構化 JSON 錯誤輸出
- `app/services/barchart_scraper_service.rb`：正確處理 scraper 回傳的 `error` 狀態（原本會誤判成 success），並記錄完整 stderr 到 log
- `app/models/leaps_option_chain_snapshot.rb`：`FRESH_WINDOW` cache 新鮮窗從 30 分鐘調整為 1 小時
- `spec/requests/csp_lessons_spec.rb`、`spec/requests/idle_timeout_spec.rb`（新增）：涵蓋登入閘門、路徑穿越防護、閒置逾時三種情境

### 2026-04-19 — 期權鏈 Tippy+KaTeX tooltip 升級、水平溢出修正、中文欄位標籤

**動機：** 單選 Calls/Puts 模式新增 TradingView 風格欄位後表格水平溢出；tooltip 說明過於簡陋，缺乏數學公式；Bid/Ask 欄位應維持中文。

**異動內容：**
- `app/frontend/option_price_tracker/components/OptionsChainTable.tsx`：安裝 `@tippyjs/react` + `katex`，以 Tippy 取代 CSS hover tooltip（支援跨 overflow 容器定位、居中顯示）；各欄位 tooltip 含 KaTeX 數學公式、中文說明、黃底範例；改用 `table-layout: fixed` + 百分比欄寬消除水平捲動；單選模式欄位標籤改回出價/要價；修正 both-mode thead 多餘欄造成的錯位

### 2026-04-17 — Options 頁面可調整框格 + Navbar 字體大小控制

**動機：** 提升 Options 頁面彈性：三個固定框格改為可拖動調整並記憶位置；Navbar 加入 5 個字體大小按鍵。

**異動內容：**
- `app/frontend/options/OptionsAnalyzerApp.tsx`：改用 `react-resizable-panels` v2，三個 `Group`/`Panel`/`Separator` 結構；`useDefaultLayout` 自動 localStorage 持久化；header 加入「↺ 還原版面」按鈕
- `app/components/fair_value/font_size_controls_component.rb`：新建，5 個遞增大小的 A 按鍵（14-18px），修改 `html` 根字體，localStorage 持久化
- `app/components/fair_value/navbar_component.rb`：AppSwitcher 右側加入字體大小控制元件
- `app/views/layouts/application.html.erb`：head 最頂加 early-paint script 防止字體閃爍 (FOUC)
- `app/assets/tailwind/application.css`：加入 resize handle 所需 CSS（cursor-col/row-resize、w/h-1.5、hover:bg-blue-400）

### 2026-03-17 — 修復歐歐分析重複點擊導致串流衝突

**動機：** 串流進行中再次點擊 🐱 按鈕會開第二條 EventSource 連線，兩條互相寫同一面板，導致分析停頓或需點第二次才出現結果。

**異動內容：**
- `app/components/daily_momentum/analysis_panel_component.rb`：新增 `streaming` 狀態物件，串流進行中防止重複觸發；`onerror` 無論 buffer 是否有內容都顯示重試按鈕

### 2026-03-17 — 切換至 Groq (Llama 3.3)，修正 Llama markdown 格式

**動機：** 使用 Groq 免費 API（llama-3.3-70b-versatile）取代 Anthropic Claude，速度更快；Llama 輸出的 markdown 標題無換行導致 Kramdown 渲染破版，需加入正規化處理。

**異動內容：**
- `app/services/ouou_analysis_service.rb`：改用 Groq API，OpenAI 相容格式（SSE streaming、messages 結構）；新增 `[MOMENTUM_TABLE]` 佔位符替換機制；更新 system prompt 為完整 markdown 範本
- `app/controllers/reports_controller.rb`：新增 `normalize_llama_output`，處理五種 Llama 格式問題（mid-line heading、##N. 無空格、表格黏標題、blockquote 黏標題）
- `app/components/daily_momentum/analysis_panel_component.rb`：標示更新為 Powered by Groq / Llama 3.3；PDF 匯出 CSS 同步調整
- `app/assets/tailwind/application.css`：md-body heading 層次更明確，blockquote 樣式強化

### 2026-03-16 — 持股結構資料修正與 UX 調整

**動機：** 修正 Yahoo Finance 回傳的持股百分比顯示錯誤、機構數量欄位名稱錯誤，並調整 UX 為手動更新模式。

**異動內容：**
- `app/services/yahoo_finance_service.rb`：修正 `pct_to_f` 將 0~1 小數 ×100 轉為百分比；修正 `institutionsCount` 欄位名稱；`pctChange` 同步換算
- `app/controllers/api/v1/ownership_snapshots_controller.rb`：時間範圍改為 1w/1m/90d；`pct_change` 加入 holder 序列化
- `app/frontend/ownership/OwnershipApp.tsx`：左側點擊只切換股票，不自動抓取；加「更新快照」手動按鈕
- `app/frontend/ownership/components/TimeRangeSelector.tsx`：範圍改為週/月/90天
- DB schema：唯一鍵恢復為 `ticker + quarter`（每季一筆，重複更新同一筆）

### 2026-03-16 — 持股結構改版：趨勢追蹤、季度比較、機構持有人詳表

**動機：** 將持股結構從「單一快照」升級為「趨勢追蹤」，支援季度對比、時間範圍篩選、機構持有人季度變化分析。

**異動內容：**
- `db/migrate/*_redesign_ownership_schema.rb`：重建 `ownership_snapshots`（ticker + quarter unique）+ 新增 `ownership_holders` 資料表
- `app/models/ownership_snapshot.rb` / `ownership_holder.rb`：改寫 Model，建立 has_many 關聯
- `app/services/ownership_snapshot_service.rb`：新建 Service，封裝 upsert / load_history / previous_snapshot 邏輯
- `app/controllers/api/v1/ownership_snapshots_controller.rb`：新增 JSON API，支援 `?range=90d|1q|6m|1y`
- `config/routes.rb`：新增 API 路由 `GET/POST /api/v1/ownership_snapshots/:ticker`
- `app/frontend/ownership/`：全面改版，新增 MetricCards、TimeRangeSelector、OwnershipTrendChart（ComposedChart + Area）、HoldersTable（季度變化 + NEW badge）、utils/format.ts

### 2026-03-16 — 新增「持股結構」工具（Vite + React + PostgreSQL 歷史快照）

**動機：** 提供 Watchlist 股票的持股結構歷史追蹤，可查看機構持股% 與內部人持股% 隨時間的變化趨勢。

**異動內容：**
- `db/migrate/*_create_ownership_snapshots.rb`：新增 `ownership_snapshots` 資料表（symbol、機構持股%、內部人持股%、top_holders JSONB、fetched_at）
- `app/models/ownership_snapshot.rb`：新增 Model，含 `history_for`、`latest_for` 類別方法
- `app/controllers/ownership_controller.rb`：新增 Controller，提供 index/history/fetch 三個 action
- `config/routes.rb`：新增 `/ownership`、`/ownership/history`、`/ownership/fetch` 路由
- `app/frontend/ownership/`：Vite + React 前端（OwnershipApp、SymbolList、OwnershipPanel、OwnershipChart），使用 Recharts 繪製折線圖
- `app/frontend/entrypoints/ownership.tsx`：React 掛載點
- `app/components/ownership/page_component.rb`：Phlex shell（渲染 `#ownership-root` 掛載 div）
- `app/views/layouts/application.html.erb`：條件性載入 ownership.tsx bundle
- `app/components/fair_value/app_switcher_component.rb`：Sidebar 新增「🏦 持股結構」入口
- `config/initializers/content_security_policy.rb`：開發環境啟用 Vite HMR（unsafe_eval + WebSocket）
- `Gemfile`：新增 `vite_rails ~> 3.0`

### 2026-03-16 — 安全性強化：CSP 啟用、ValuationService 測試、open_timeout 修正

**動機：** Rails 審計發現三項安全/品質問題：CSP header 未啟用、核心估值邏輯 0% 測試覆蓋率、Groq API 連線無 open_timeout 可能永久阻塞 worker。

**異動內容：**
- `config/initializers/content_security_policy.rb`：啟用 Content Security Policy，設定 `default_src :self`、`script_src/style_src` 允許 `cdn.jsdelivr.net` 及 `unsafe_inline`（NProgress inline script）、`connect_src :self`（SSE streaming）、`object_src/frame_ancestors :none`
- `app/services/ouou_analysis_service.rb`：`Net::HTTP.start` 加入 `open_timeout: 10`，防止 Groq API 不可達時 worker 永久阻塞
- `spec/services/valuation_service_spec.rb`：新增 ValuationService 測試，33 個 examples 涵蓋股票分類、成長率估算、估值方法選擇、nil 邊界條件、整合測試及 judgment 判斷邏輯

### 2026-03-12 — Portfolio 持股點擊浮動面板（機構/大戶持股佔比）

**動機：** 讓使用者在持股頁面快速查閱任意股票的機構持股比例與主要大戶名單，無需離開頁面。

**異動內容：**
- `app/services/yahoo_finance_service.rb`：新增 `holders(symbol)` 方法，呼叫 Yahoo Finance quoteSummary API 取得 `majorHoldersBreakdown` 與 `institutionOwnership`
- `config/routes.rb`：新增 `GET /portfolio/ownership` 路由
- `app/controllers/portfolios_controller.rb`：新增 `ownership` action，回傳 JSON
- `app/components/portfolio/holding_row_component.rb`：`render_symbol` td 加上 `data-ownership-symbol` 屬性與 cursor-pointer
- `app/components/portfolio/holding_list_component.rb`：新增 `render_ownership_modal` 方法（浮動面板 HTML）與對應 JS（fetch、渲染、ESC/backdrop 關閉）

### 2026-03-12 — 建立 docs 目錄與三份主要文件

**動機：** 為專案建立完整文件體系，提升可維護性與交接效率。

**異動內容：**
- 新增 `docs/` 目錄
- 新增 `docs/INSTALL.md`：系統需求、安裝步驟、環境變數、常見問題
- 新增 `docs/USER_MANUAL.md`：功能操作說明、JSON API 範例
- 新增 `docs/ARCHITECTURE.md`：設計原則、技術棧、資料流程、元件說明

**設定更新：**
- `CLAUDE.md`（專案）：新增文件規範區塊
- `~/.claude/CLAUDE.md`（全域）：新增「建立新 app 必須建立 docs 目錄」規則

**異動檔案**

| 檔案 | 異動類型 |
|------|----------|
| `docs/INSTALL.md` | 新建 |
| `docs/USER_MANUAL.md` | 新建 |
| `docs/ARCHITECTURE.md` | 新建 |
| `CLAUDE.md` | 新增文件規範區塊 |

---

### 2026-03-11 — 移除 CDN 依賴，改用本地資源

**動機：** 消除對外部 CDN 的執行期依賴，提升可靠性與安全性。

**Markdown 渲染（marked.js → kramdown）**

- 移除 `cdn.jsdelivr.net/npm/marked` CDN script
- 新增 `kramdown` gem（伺服器端渲染）
- `ReportsController#company_news`：將 `content_md` 欄位改為伺服器端預先渲染成 `content_html`（HTML 字串）後回傳 JSON
- 新增 `POST /momentum/render_markdown` endpoint：供歐歐 AI 分析 SSE 串流結束後，將完整 markdown 文字送至伺服器轉成 HTML 再注入頁面
- `DailyMomentum::NewsTabPanelComponent`：改用 `content_html`，移除 `marked.parse()` 呼叫
- `DailyMomentum::AnalysisPanelComponent`：SSE `[DONE]` 後改以 `fetch POST /momentum/render_markdown` 取得 HTML

**Tailwind CSS（CDN → 本地編譯）**

- 移除 `cdn.tailwindcss.com` CDN script（原存在於 `application.html.erb`、`component_preview.html.erb`、`FairValue::PageLayoutComponent`）
- 新增 `tailwindcss-rails` gem，執行 `tailwindcss:install` 初始化
- 編譯輸出：`app/assets/builds/tailwind.css`（由 propshaft 提供）
- 原 `application.html.erb` inline `<style>` 區塊（`.md-body` 樣式、NProgress 顏色）移至 `app/assets/tailwind/application.css`

**異動檔案**

| 檔案 | 異動類型 |
|------|----------|
| `Gemfile` | 新增 `kramdown`, `tailwindcss-rails` |
| `config/routes.rb` | 新增 `POST /momentum/render_markdown` |
| `app/controllers/reports_controller.rb` | 新增 `render_markdown` action；`company_news` 改回傳 `content_html` |
| `app/assets/tailwind/application.css` | 新建；移入 `.md-body` 與 NProgress 樣式 |
| `app/views/layouts/application.html.erb` | 移除 CDN scripts/styles；改用 `stylesheet_link_tag "tailwind"` |
| `app/views/layouts/component_preview.html.erb` | 同上 |
| `app/components/fair_value/page_layout_component.rb` | 移除硬編碼 Tailwind CDN script |
| `app/components/daily_momentum/analysis_panel_component.rb` | 改用 `fetch POST` 取得伺服器端渲染 HTML |
| `app/components/daily_momentum/news_tab_panel_component.rb` | 改用 `content_html` |

---

### 2026-03-11 — 強化歐歐分析品質與效能

**動機：** 補充更豐富的技術面數據給 AI 分析，並消除 `fetch_stocks` 的序列 HTTP 瓶頸。

**分析品質提升（`OuouAnalysisService`）**

- 新增「52週位置」：計算現價在52週區間的百分位（%），並附距高點/低點距離
- 新增「20日動量」：原本只有5日動量，現在同時提供20日動量供趨勢判斷
- 新增「成交量 vs 20日均量」：判斷是否放量，格式：`今日量 vs 均量（比率%）`
- `compute_momentum` 重構為接受 `days` 參數，統一5日/20日計算邏輯

**Yahoo Finance 資料擴充（`YahooFinanceService`）**

- 新增 `volumes` 陣列（從 `indicators.quote.volume` 取出），供均量計算使用
- `empty_result` 同步補上 `volumes: []`

**效能優化（`MomentumReportService`）**

- `fetch_stocks` 改為平行化：每個 symbol 各開一個 Thread 同時呼叫 Finnhub + Yahoo
- 原本5個 symbol 最差需等待 100 秒（序列），現在縮短為單次 timeout（10秒）

**異動檔案**

| 檔案 | 異動類型 |
|------|----------|
| `app/services/yahoo_finance_service.rb` | 新增 `volumes` 陣列欄位 |
| `app/services/momentum_report_service.rb` | `fetch_stocks` 平行化，抽出 `fetch_stock` 私有方法 |
| `app/services/ouou_analysis_service.rb` | 新增 `position_in_52w`、`volume_vs_avg`、`fmt_vol`；`compute_momentum` 接受 `days` 參數；prompt 加入三項新指標 |

---

### 2026-03-11 — 修正 Markdown 表格無法正確渲染

**問題：** Claude 生成的 markdown 表格使用 GFM 格式（`|---|---|`），但 `Kramdown::Document.new(text)` 預設使用 kramdown 自己的 parser，對 GFM 表格相容性不足，導致 pipe 字元全部輸出為純文字，表格完全走版。

**修正：**

- 新增 `kramdown-parser-gfm` gem
- 所有 `Kramdown::Document.new(text)` 改為 `Kramdown::Document.new(text, input: "GFM")`，使用 GFM parser 解析

**異動檔案**

| 檔案 | 異動類型 |
|------|----------|
| `Gemfile` | 新增 `kramdown-parser-gfm ~> 1.1` |
| `app/controllers/reports_controller.rb` | `render_markdown` 與 `company_news` 兩處改用 `input: "GFM"` |

---

### 2026-03-11 — 修正 em-dash 破折號導致表格仍然壞版及標題不解析

**問題：** Claude 在 table separator row 使用中文破折號 `——`（U+2014）而非 ASCII `-`，即使 GFM parser 也無法識別此 separator，導致整個表格被當成純文字段落輸出，並連帶使後續 `###` 標題無法正確解析。

**修正：**

- 新增 `normalize_md_separators` 私有方法：逐行掃描，若某行符合「全由 `|`、空白、`-`、`:`、`—`、`–` 組成」的 separator 特徵，則將破折號替換為 `---`
- 新增 `render_gfm` 私有方法統一呼叫流程：`normalize → Kramdown GFM → HTML`
- `render_markdown` action 與 `company_news` 改用 `render_gfm`

**異動檔案**

| 檔案 | 異動類型 |
|------|----------|
| `app/controllers/reports_controller.rb` | 新增 `render_gfm`、`normalize_md_separators` 私有方法 |

---

### 2026-03-11 — 歐歐分析結果 3 小時 Cache

**動機：** 同一股票在 1 小時內重複按下分析按鈕，不應重新呼叫 Groq API，直接回傳快取內容，節省 API 費用並提升回應速度。

**實作方式（純 server 端，JS 無需改動）：**

- Cache key：`ouou_analysis:{SYMBOL}`，TTL 3 小時
- **Cache hit**：`OuouAnalysisService#call` 直接 yield 完整快取文字，controller 照常寫入 SSE stream，client 端收到後一次性觸發 `[DONE]` → `renderMarkdown`，體驗與首次相同，僅速度差異
- **Cache miss**：串流過程中累積所有 chunks，串流結束後寫入 `Rails.cache`

**異動檔案**

| 檔案 | 異動類型 |
|------|----------|
| `app/services/ouou_analysis_service.rb` | 新增 `CACHE_TTL`、`CACHE_PREFIX` 常數；`call` 加入 cache 讀寫邏輯；新增 `cache_key` 私有方法 |

---

### 2026-03-11 — 歐歐分析匯出 PNG / PDF，並附加分析日期

**動機：** 讓使用者可將歐歐分析結果儲存為 PNG 圖片或列印成 PDF，並在文末標記分析時間。

**分析日期標記（`OuouAnalysisService`）**

- 串流完成後自動 append markdown footer：`*📌 歐歐分析時間：YYYY-MM-DD HH:MM ET*`
- 連同日期一起寫入 cache，cache hit 時日期也自動帶出
- 日期以 italic 段落呈現在分析面板底部

**匯出功能（`AnalysisPanelComponent`）**

- `renderMarkdown` 完成後，在分析內容下方加入兩個按鈕：**⬇ 下載 PNG**、**⬇ 下載 PDF**
- **PNG**：`html2canvas` 擷取 `.md-body` div（含日期），scale=2 高解析度，下載檔名格式 `{SYMBOL}_歐歐分析_{DATE}.png`
- **PDF**：開新視窗並注入完整 CSS（含 `.md-body` 所有樣式），呼叫 `window.print()` 讓瀏覽器另存 PDF

**異動檔案**

| 檔案 | 異動類型 |
|------|----------|
| `app/services/ouou_analysis_service.rb` | 新增 `analysis_date_footer` 方法；串流完成後 emit footer chunk 並寫入 cache |
| `app/views/layouts/application.html.erb` | 新增 `html2canvas@1.4.1` CDN script |
| `app/components/daily_momentum/analysis_panel_component.rb` | `renderMarkdown` 加入匯出按鈕；新增 `exportPng`、`exportPdf` 函式與 click 委派 |

### 2026-04-17 — Options 頁面三框格可調整大小 + Navbar 字體大小控制

**新增功能**

- `react-resizable-panels` v4 接入 Options 頁面，支援三組可拖動邊界（左側 sidebar / 損益圖 / 策略列表）
- 各面板位置自動記憶至 localStorage（`react-resizable-panels:options-*`）
- Header 新增「↺ 還原版面」按鈕，一鍵恢復預設比例（13/87/34/66/22/78%）
- Navbar AppSwitcher 右側加入五個字體大小按鍵（14–18px），含 `fairprice:font-size` localStorage 記憶與早期渲染腳本（防 FOUC）

**修正 Bug**

- `react-resizable-panels` v4 Panel 尺寸 prop 必須為字串百分比（如 `"13%"`），傳入純數字會被解讀為 px，導致面板被 maxSize 鎖死在 ~2%
- `options-root` 缺少 `flex flex-col`，造成 React `h-full` 失效、Group 高度僅 288px（修正後 517px）
- React 根容器改為 `flex-1 min-h-0`，確保在 flex 父容器中正確撐開高度

**涉及檔案**

| 檔案 | 說明 |
|------|------|
| `app/frontend/options/OptionsAnalyzerApp.tsx` | 主要改寫：Panel 尺寸改字串 %、根容器高度修正 |
| `app/components/options/page_component.rb` | 加入 `flex flex-col` 解決高度鏈問題 |
| `app/components/fair_value/font_size_controls_component.rb` | 新建：5 個字體大小按鍵元件 |
| `app/components/fair_value/navbar_component.rb` | 加入 FontSizeControls |
| `app/views/layouts/application.html.erb` | 加入早期渲染字體大小腳本 |
| `app/assets/tailwind/application.css` | 新增 resize handle 靜態 class 定義 |
| `package.json` | 新增 react-resizable-panels ^4.10.0 |

### 2026-04-03 — routes.rb 重構：抽常數、改用 resources

整理 `config/routes.rb`，消除重複定義與手動展開的 REST 路由。

**異動內容**

- 抽出 `TICKER_CONSTRAINT` 常數，取代原本分散在 7 處的相同正規表達式
- `api/v1/margin_positions`：手動 `get price_lookup` + 手動 `post close` 改用 `resources` + `collection`/`member` block
- `watchlist`：9 條手動路由改用 `resources :watchlist_alerts, controller: :stock_alerts`
- `portfolio`：8 條手動路由改用 `resources :portfolios`，collection 補上 `ocr_import`/`reorder`/`quotes`/`ownership`
- 同步更新 named route helper：`watchlist_path` → `watchlist_alerts_path`、`portfolio_index_path` → `portfolios_path`

**異動檔案**

| 檔案 | 異動類型 |
|------|----------|
| `config/routes.rb` | 重構 |
| `app/controllers/stock_alerts_controller.rb` | 更新 named route helper |
| `app/controllers/portfolios_controller.rb` | 更新 named route helper |
| `app/components/stock_alert/alert_form_component.rb` | 更新 named route helper |
| `app/components/stock_alert/alert_list_component.rb` | 更新 named route helper |

---

### 2026-03-31 — 技術圖表：lightweight-charts 蠟燭圖、S&R 線、RSI 雙線

重寫 `TechnicalsChart.tsx`，從 Recharts 改用 lightweight-charts（TradingView 開源）。

**主要功能**

- 蠟燭圖（K 線）取代折線圖
- 支撐/阻力線：`createPriceLine()` 直接標註在 Y 軸（阻力橘、支撐翠綠）
- RSI14（紫）/ RSI7（藍）雙線，`lastValueVisible: true` 在軸上顯示即時數值
- 時間範圍新增 1D（5 分線）、5D（15 分線），日內不顯示 S&R
- 後端 `calc_rsi` 修正為 Wilder's EMA（非簡單平均）
- `YahooFinanceService` 補齊 open/high/low 欄位，zip 後過濾 nil-close bars

**防錯工具（同日新增）**

- `eslint.config.js`：`eslint-plugin-react-hooks` — 自動 hook 於每次 TSX 編輯後執行
- `spec/requests/api/v1/charts_rsi_spec.rb`：鎖定 Wilder's EMA 算法，7 examples
- `stories/TechnicalsChart.stories.tsx`：Chromatic 三種寬度視覺回歸（1280/768/375px）

**異動檔案**

| 檔案 | 異動類型 |
|------|----------|
| `app/frontend/technicals/TechnicalsChart.tsx` | 完整重寫，Recharts → lightweight-charts |
| `app/controllers/api/v1/charts_controller.rb` | 新增 1D/5D range、open/high/low、Wilder's RSI |
| `app/services/yahoo_finance_service.rb` | 補齊 OHLC，zip 過濾 nil-close |
| `eslint.config.js` | 新增（ESLint + react-hooks + typescript-eslint）|
| `spec/requests/api/v1/charts_rsi_spec.rb` | 新增（RSI 算法單元測試）|
| `stories/TechnicalsChart.stories.tsx` | 新增（Chromatic 視覺回歸）|

### 2026-08-18 — 新增每日強制登出（24 小時絕對逾時）

- 除了原本的「閒置 2 小時登出」，新增「登入滿 24 小時強制登出」，即使持續有活動也一樣，避免瀏覽器分頁長期開著不關導致 session 一直存活。
- 登入時（`SessionsController#google_callback`）記錄 `session[:login_at]`，`ApplicationController#enforce_absolute_timeout` 每次請求檢查是否超過 24 小時。
- `IDLE_TIMEOUT_EXEMPT_EMAIL`（`mr.idarfan@gmail.com`）沿用既有排除設定，兩種逾時機制皆不套用在此帳號。
- 動機：`/track`、`/api` 皆在 `GATE_EXEMPT_PREFIXES`，不會觸發閒置檢查，若分頁不關、只靠背景 sendBeacon 心跳，session 可能無限期存活，導致帳戶管理頁的「累積停留時間」失真。強制每日登出可限制單一 session 的最長存活時間。

**異動檔案**

| 檔案 | 異動類型 |
|------|----------|
| `app/controllers/application_controller.rb` | 新增 `ABSOLUTE_SESSION_TIMEOUT` 常數與 `enforce_absolute_timeout` |
| `app/controllers/sessions_controller.rb` | 登入時記錄 `session[:login_at]` |
| `spec/requests/absolute_timeout_spec.rb` | 新增（24 小時強制登出測試，含排除帳號）|

### 2026-08-18 — 帳戶管理列表新增每日停留時間拆分

- 「累積停留時間」欄位維持全部歷史加總的總使用時數不變；新增可展開的近 7 天每日拆分（`<details>/<summary>`），方便判斷總數字是長期累積還是單日異常暴增。
- `Admin::UsersController#index` 新增 `daily_dwell_by_user`，沿用既有 `UserActivity.recent`（7 天）scope，依日期分組加總 `duration_ms`。
- `Admin::Users::PageComponent` / `RowComponent` 新增 `daily_dwell` 參數並傳遞、渲染。

**異動檔案**

| 檔案 | 異動類型 |
|------|----------|
| `app/controllers/admin/users_controller.rb` | 新增 `daily_dwell_by_user` |
| `app/components/admin/users/page_component.rb` | 新增 `daily_dwell` 參數 |
| `app/components/admin/users/row_component.rb` | 新增 `daily_dwell` 參數與可展開的每日拆分渲染 |
| `app/views/admin/users/index.html.erb` | 傳入 `daily_dwell` |
| `spec/requests/admin_users_spec.rb` | 新增每日拆分測試 |
