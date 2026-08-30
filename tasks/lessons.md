# 專案教訓紀錄

## 2026-08-30 — CSP style-src 收斂

### 教訓 A：nonce 對 style 屬性無效，只對 `<style>` 區塊有效

script-src 收斂時的做法（把唯一的內嵌 script 加 nonce）在 style-src **完全不適用**。
`style="..."` 屬性沒有辦法用 nonce 放行，只能真的移除。

三種替代承載：
```
靜態樣式  → CSS class
動態數值  → data attribute + CSSOM（el.style.width = ...）
            CSSOM 賦值不受 CSP 限制，被擋的只有「HTML 屬性」這個形式
<style>   → nonce（有效）
```

innerHTML 組出來的字串裡的 `style="..."` **一樣會被擋**（走的是 HTML 解析），
不要以為 JS 產生的就沒事。

### 教訓 B：`after_action` 設 Report-Only 標頭會關掉主 CSP

```ruby
# ActionDispatch::ContentSecurityPolicy::Middleware
return response if policy_present?(headers)

def policy_present?(headers)
  headers[CONTENT_SECURITY_POLICY] || headers[CONTENT_SECURITY_POLICY_REPORT_ONLY]
end
```

判斷是「**或**」。controller 的 `after_action` 比 middleware 早跑，先放上
Report-Only 標頭就會讓 middleware 認定政策已存在，**整個跳過主政策**——
主 CSP 標頭直接消失，而且沒有任何錯誤訊息。

要另外送 Report-Only 標頭，必須用 middleware 並 `insert_before` 掛在
Rails CSP middleware 外層（回應階段才會在它之後執行）。

也不要用 `config.content_security_policy_report_only`——那會讓**整份**政策
變成報告模式，連已經收緊的指令也一起失去強制力。過渡期不該用安全倒退
換取觀測能力。

### 教訓 C：Playwright 的 console 抓不到 CSP 違規

CSP 違規走 CDP 的 `Log.entryAdded`，Playwright 的 `page.on('console')` 只收
`Runtime.consoleAPICalled`，**收不到瀏覽器產生的安全訊息**。

可靠的量測方式（由好到差）：
```
1. 直接解析伺服器送出的 HTML —— 最精確，DOM 裡的 style 屬性有些是
   JS 用 CSSOM 設的，那些 CSP 根本不管
2. 在頁面載入「之前」掛 securitypolicyviolation 事件監聽
   （注意：用 iframe 做這件事會被 frame-ancestors 擋掉）
3. console —— 最不可靠
```

### 教訓 D：逐行的字串替換會製造重複的 hash key，而且是靜默的

`class:` 與 `style:` 分屬不同行時，把 `style:` 換成 `class:` 會讓同一個呼叫
有兩個 `class` 鍵。Ruby 的 hash 是後者覆蓋前者，**原本的 class 整串消失**，
不會報錯——是截圖比對才發現卡片內距不見了。

**定位重複 key 用 Ruby 自己的警告，不要自己寫正規式：**
```bash
ruby -w -c path/to/component.rb 2>&1 | grep duplicated
# → "key :class is duplicated and overwritten on line N"
```
自己寫的括號深度追蹤會把相鄰的 span 誤判成同一個呼叫——我那次誤判
還把某個 span 的 class 整個吃掉。

改完 Phlex 元件後跑一次全掃描：
```ruby
Dir["app/components/**/*.rb"].each { |f| ... `ruby -w -c #{f}` ... }
```

### 教訓 E：Tailwind 掃描器的限制只適用於它產生的 utility

`text-[#{px}px]` 這種插值組出來的 **Tailwind utility** 不會被編進 CSS
（掃描器只認原始碼裡出現過的完整字串）。

但**自己寫在 application.css 的 class 沒有這個問題**——
`"bcvs-card-#{spec[:slug]}"` 完全沒問題，因為那條規則永遠存在於 CSS 裡。
這個區別在決定「要用 Tailwind arbitrary value 還是自訂 class」時很關鍵。


## 2026-08-30 — 靜態稽核工具的「全部修掉」是錯誤目標

### 教訓 A：修之前先問「這個驗證會不會執行」

`database_consistency` 建議 8 張 snapshot 表加 uniqueness 驗證器。
查證後發現這些表全部由 `upsert` / `insert_all` 寫入——**這兩個 API 完全跳過
ActiveRecord 驗證**。照著加的結果是：永遠不執行的死碼、每次 `.create` 多一次
SELECT、以及「這張表有唯一性驗證」的假象。

**防治規則：**
```
稽核工具建議加驗證時，先確認該 model 的實際寫入路徑：
  * upsert / insert_all / update_all / 直接 SQL → 驗證不會執行
  * 成本不對稱：presence 驗證免費，uniqueness 每次存檔多一次 SELECT
  * 決定不修的，理由要寫進工具的設定檔——不是寫在 commit message 裡
    （下一個人跑報告時看到的是設定檔，不是 git log）
```

### 教訓 B：`case_sensitive: false` 讓唯一性驗證用不到索引

```ruby
validates :symbol, uniqueness: { scope: :user_id, case_sensitive: false }
```
產生的是 `LOWER(symbol) = LOWER($1)`，**用不到 `(user_id, symbol)` 這個 btree 索引**。
若欄位本來就會 `upcase` 正規化，這個選項是純粹的浪費。

同時它會讓 `database_consistency` 一次報兩項（索引沒驗證器 + 應建 `lower()` 索引）——
看起來像兩個問題，其實是同一個。

### 教訓 C：正規化必須在 `before_validation`，不是 `before_save`

```ruby
before_save { self.symbol = symbol.upcase }        # ← 驗證跑在未正規化的值上
validates :symbol, uniqueness: true
```
使用者送 `aapl`：唯一性驗證比對 `'aapl'`（沒撞到）→ 通過 → 存檔時 upcase 成
`AAPL` → 撞上唯一索引 → **使用者看到 500 而不是驗證錯誤**。

format 驗證也一樣：`" aapl "` 會因為前後空白被 format 擋掉，
因為 strip 發生在驗證之後。

```
正規化（upcase / strip / squish）一律放 before_validation。
放 before_save 的唯一正當理由是「這個轉換不影響任何驗證」——
而那幾乎不存在。
```

### 教訓 D：冗餘索引的判定要自己驗，工具不看 `WHERE`

`RedundantIndexChecker` 報「A 被 B 涵蓋」時，只比對欄位順序，
**不檢查 B 是不是 partial index**。帶 `WHERE` 條件的複合索引不能涵蓋單欄索引。

刪索引前一律先查：
```sql
SELECT indexname, indexdef FROM pg_indexes WHERE indexname IN (...);
```
這次 7 個全部驗證屬實（沒有 partial），但那是查過才知道的。

### 教訓 E：兩條 lint 規則可能互相牴觸，那是「檔案該拆」的訊號

一支跨四個 model 的 spec 同時被 `RSpec/DescribeClass`（要類別不要字串）與
`RSpec/MultipleDescribes`（要單一 top-level）夾住，怎麼寫都不對。

這不是規則有問題，是**檔案結構有問題**——正解是拆進各自 model 的 spec。
遇到互相牴觸的 lint 規則，先想「它們是不是在指同一件事」。


## 2026-08-30 — 停更的 gem 未必需要替代 gem

### 教訓 A：先問「這個功能是不是已經進了框架」

`traceroute`（偵測路由／action 不匹配）停更於 2020-04-28。第一直覺是找替代 gem，
但它的一半功能從 **Rails 7.1 起就是內建的 `rails routes --unused`**。

停更的第三方工具往往正是因為功能被上游吸收才停更。找替代品之前，先查框架
本身的 CHANGELOG 與 `rails --help` / `rake -T`。

### 教訓 B：Rails 把 controller 上每一個 public method 都當成可路由的 action

```ruby
class Api::V1::ChartsController < Api::V1::BaseController
  include Charts::TechnicalIndicators   # ← 模組的 6 個 public 方法全都變成 action
end
```

`include` 進 controller 的模組，其 public 方法會進入 `action_methods`，
跟真正的 action 只差一條路由。純計算模組必須降級：

```ruby
private(*Charts::TechnicalIndicators.public_instance_methods)
```

用 splat 而非逐一列名——之後在模組新增方法會自動涵蓋，不會因為漏改而重新曝露。

### 教訓 C：稽核腳本值得升格成 spec

臨時寫的 `bin/rails runner` 探針只在跑的那一刻有效。改寫成
`spec/routing/unreachable_actions_spec.rb` 之後就進了 CI，每次都會跑。
本專案已有同型前例：`spec/frontend/behavior_registry_spec.rb`
（釘住 `data-behavior` 與模組註冊的對應）。

**升格時務必反向驗證**：把修好的地方暫時還原，確認測試會紅。
本次驗過——註解掉 `private(...)` 那行，測試立刻失敗。沒驗過的守門測試等於沒有。

### 教訓 D：`eager_load!` 會灌水覆蓋率數字

新 spec 需要 `Rails.application.eager_load!` 才能列舉所有 controller，
副作用是全部類別的 body 被執行一次，那些行被 SimpleCov 算成「已覆蓋」。

**line 覆蓋率因此從 51.72% 跳到 58.36%，測試強度一點都沒變。**
branch 覆蓋率不受影響（40.59% → 41.08%）。

```
覆蓋率數字看 branch 不看 line：
  * line 會被 class body、常數定義、require 灌水
  * eager_load! / 大量 model 載入都會推高 line 而不推高 branch
  * 門檻調整時要記錄「為什麼水位變了」，否則下次沒人知道那 6 個百分點是假的
```


## 2026-08-30 — 「工具裝了」不等於「工具在跑」

### 教訓 A：帶 `--ensure-latest` 的 binstub 會在版本落後時整個不執行

`bin/brakeman` 注入 `--ensure-latest`。本機 8.0.5、上游 8.0.6，Brakeman 就在
**掃描開始前** exit 5，輸出只有一行「Brakeman 8.0.5 is not the latest version 8.0.6」。

`bin/ci` 的資安步驟因此長期空轉。危險之處在於**失敗長得不像失敗**——沒有 stack trace、
沒有「scan failed」，只有一行版本提示，很容易被當成無害的雜訊略過。

**防治規則：**
```
稽核／掃描工具接進 CI 後，必須確認它「真的掃了東西」，不能只看 exit code：
  * 找輸出裡的規模證據——掃了幾個檔、幾個 controller、跑了哪些 check
  * exit 0 + 輸出只有一兩行 = 高度可疑，先當成沒跑
  * 有 --ensure-latest / --strict 這類 binstub 注入時，先確認版本是最新
```

### 教訓 B：CI 設定要逐行讀，別假設「有 CI 就有測試」

`config/ci.rb` 有 Setup / RuboCop / bundler-audit / Brakeman 四步，看起來很完整，
**但一行 spec 都沒跑**。lint 全綠、資安全綠，測試從來沒進過 CI。

**防治規則：** 接手或稽核專案時，把 CI 設定檔整份讀完並逐步驟問「這一步實際執行什麼」，
不要因為檔案存在、步驟數量看起來合理就跳過。

### 教訓 C：導入 linter 時，永遠紅的閘門等於沒有閘門

`rubocop-rspec` 一開就是 657 個 offense。若原樣接進 CI，結果只有兩種：
CI 永遠紅沒人看，或立刻被整包關掉——兩種都等於沒裝。

實際分佈：**0 個缺陷偵測類**（`RepeatedDescription`、`EmptyExampleGroup`、`VoidExpect`
全部沒觸發），597 個集中在八個風格偏好 cop。其中 `ContextWording` 要求 context 描述以
英文 `when`/`with` 開頭，本專案 spec 一律寫繁中——這條規則對本專案在結構上就不適用。

**防治規則：**
```
導入新 linter 的四步：
  1. 先跑一次，用 --format json 統計「每個 cop 各幾個」，不要只看總數
  2. 分兩堆：缺陷偵測 vs 風格偏好。前者留、後者對照專案實況決定
  3. 關掉的每一條都要在設定檔寫明理由，量體太大而暫緩的標 TODO + 數量
  4. 剩下的必須修到 0，閘門才有意義
```

### 教訓 D：`describe` 區塊裡宣告常數 = 定義在全域 `Object` 上

```ruby
RSpec.describe Foo do
  SPOT = 14.46          # ← 這是 Object::SPOT，不是 describe 的區域變數
end
```
兩支 spec 用同名常數會互相覆寫，且因為 Ruby 只在重新指派時警告、單純讀取不會，
問題會以「某支 spec 單獨跑會過、整包跑就掛」的形式出現，極難追。改用 `let`。

### 教訓 E：驗證第三方 gem 的設定有沒有生效，要找副作用不要讀 getter

驗證 `Bullet.bullet_logger = true` 時讀 `UniformNotifier.customized_logger` 得到 `nil`，
一度以為設定沒生效，往下追了三輪。實際上那個 getter 的語意跟 setter 不對稱，設定是好的。

**真正有效的驗證是找 setter 的副作用**——`bullet_logger=` 會開啟 `log/bullet.log`，
砍掉檔案再重新 boot，檔案有沒有被建出來就是答案。後續再用一段刻意的 N+1 查詢
確認端到端會偵測、會寫 log、且不拋錯。

```
驗證外部套件設定的優先順序：
  1. 副作用（建立了什麼檔、插入了什麼 middleware、寫了什麼 log）
  2. 端到端行為（餵一個該被抓到的案例，看有沒有被抓到）
  3. getter ← 最不可靠，getter 與 setter 語意常常不對稱
```

### 教訓 F：靜態稽核工具的發現要逐條驗，不要照單全收

`database_consistency` 報 40 項，其中 4 筆 `MissingUniqueIndexChecker` 建議加
`lower(symbol)` 唯一索引。逐一讀 model 後發現**全是誤報**——那四個 model 都有
`before_validation`／`before_save` 把代號 `upcase`，DB 裡只會有大寫，
現有的 case-sensitive 索引已經足夠。

照單全收會產出 4 個沒必要的 migration，而且是動在 dev/prod 共用的資料庫上。


## 2026-04-17 — react-resizable-panels v4 + CSS 高度鏈三個教訓

### 教訓 A：npm 套件裝完必須讀 `.d.ts`，不能從文件/記憶寫 code

**過錯：** 計畫基於 v2 文件研究，但裝上的是 v4。v4 Panel 的 `defaultSize`/`minSize`/`maxSize` 傳入純數字會被解讀為 **px**（非 %）。`maxSize={25}` = 25px = ~1.96% 容器寬，sidebar 被硬鎖，`setLayout()` 也因此無效。

**診斷關鍵：** `panel.style.flexGrow = "1.962"` 而非 "13"；`25px / 1273px = 1.963%`，精確吻合。

**防治規則：**
```
引入新 npm 套件三步驟（必做，不可跳過）：
1. 確認 package.json 裡實際安裝的 semver（npm install 後版本可能比預期高）
2. head -80 node_modules/<pkg>/dist/*.d.ts   ← 讀實際型別
3. 查 CHANGELOG 或 README 確認有無 breaking change
禁止直接從文件/記憶/計畫寫 code，必須先確認實際型別。
```

**本例正確格式：**
```tsx
// ✅ v4 Panel 尺寸一律用字串百分比
<Panel defaultSize="13%" minSize="8%" maxSize="25%">
// setLayout 的 layout 物件用 0-100 數字（%），與 Panel prop 格式不對稱
ref.current?.setLayout({ "lr-sidebar": 13, "lr-main": 87 })
```

---

### 教訓 B：全高佈局改前必須追蹤 CSS 高度鏈

**過錯：** `options-root` 缺少 `flex flex-col`，React `h-full` 失效，Group 只有 288px（應 517px）。改之前截圖已顯示所有面板壓扁在左上角，但誤判成 localStorage 問題沒有繼續追查。

**防治規則：**
```
新增任何 h-full / flex-1 / overflow-hidden 容器前，
先用 browser_evaluate 量從 body 到目標元素的每一層高度：
  root → main → outer-div → react-div → group
確認每層 getBoundingClientRect().height 與預期一致，
再動手寫 code。
```

改用 `flex-1 min-h-0` 比 `h-full` 更可靠，因為不依賴父層有明確 height。

---

### 教訓 C：截圖異常就要量數字，不要跳過繼續

**過錯：** 第一張截圖看到 sidebar 顯示垂直字（壓扁狀態），應立即 `browser_evaluate` 量 `panel.style.flexGrow`，就能在 5 分鐘內定位問題。但選擇先假設是 localStorage 壞掉，多繞了一大圈。

**防治規則：**
```
截圖看到佈局異常（壓扁、消失、重疊）：
  Step 1：browser_evaluate 量 flexGrow / getBoundingClientRect()
  Step 2：確認數字與預期一致
  Step 3：追因（高度/寬度/minSize/maxSize）
  禁止只看截圖猜原因，數字是唯一的事實。
```

---

## 2026-03-26 — Options Analyzer UI 修改的五個教訓

### 教訓 1：移除預設值時必須全域搜尋

**過錯：** 移除 AAPL 預設值時，只改了 `OptionsAnalyzerApp.tsx` 裡的 `useState(initialSymbol || 'AAPL')`，遺漏了 `entrypoints/options.tsx` 的 `symbol || 'AAPL'`，導致使用者反映「AAPL 圖示還在」。

**防治：** 修改任何預設值/常數時，先執行 `Grep` 搜尋該值在整個 `app/frontend/` 目錄的所有出現位置，確認全部改完再交付。一個值可能在 entrypoint、元件、測試中各出現一次。

### 教訓 2：前端→後端數據傳遞不能假設使用者操作順序

**過錯：** 設計 `HeaderUploadZone` 傳送 `context={{ symbol, price, ivRank }}` 到後端，但沒考慮使用者可能**先上傳截圖、還沒輸入代號**，導致 `ivRank` 為 null、所有數據為空，AI 建議寫出「IV 數據未提供」。

**防治：** 凡是前端傳送的 context 數據，後端必須有**自主補齊機制**（fallback enrichment）。不能依賴使用者按特定順序操作。本次修正：後端先用 Groq 快速辨識 symbol，再自動呼叫 `IvRankService` 補齊數據。

**規則：** 後端 service 接收外部數據時，必須對每個關鍵欄位做 `present?` 檢查，缺少的自行查詢補齊，而非原樣傳給下游。

### 教訓 3：固定尺寸的 UI 元素在密集排列時必然重疊

**過錯：** Block 元件的 emoji icon 用 `w-10 h-10`（40×40px）獨立方塊，搭配 `gap-6`（24px）間距，在策略解說有 8 個區塊時，圖示背景色方塊互相重疊。

**防治：** 重複出現的區塊元件，icon 改用 inline 方式（emoji 直接放在標題文字旁），不要用獨立的方塊容器。獨立方塊只適合單一、不重複的場景（如 hero section）。

### 教訓 4：Rails server 重啟必須完整清理

**過錯：** `systemctl --user restart fairprice` 反覆失敗，進入 restart loop（計數到 10+），原因是舊 PID 檔殘留 + port 3003 被佔用。

**防治：** Rails server 重啟 SOP（已在 CLAUDE.md 規範但未嚴格遵守）：
```bash
systemctl --user stop fairprice
sleep 2
fuser -k 3003/tcp 2>/dev/null
rm -f tmp/pids/server.pid
systemctl --user reset-failed fairprice 2>/dev/null
systemctl --user start fairprice
```
必須**先 stop、再 kill port、再刪 PID、最後 start**，不能直接 restart。

### 教訓 5：修改 TypeScript 介面時必須同步修改所有引用處

**過錯：** 在 `HeaderUploadZone` 中使用 `context.ivRank.current_hv` 但 `IvRankData` type 還沒更新，用 `as Record<string, unknown>` 強轉繞過 TS 錯誤。同時 `handleOcrResult` 簽名改了但呼叫處沒同步。

**防治：**
1. **先改 type 定義，再改使用處** — 順序不能反
2. **禁止 `as Record<string, unknown>`** — 這是在掩蓋型別不一致，應該先修正 interface
3. 修改 callback 簽名時，同時修改所有呼叫處和所有傳入該 callback 的 prop

## 2026-03-30 — 技術圖表重構的五個教訓

### 教訓 1：實作財務指標前必須查標準定義

**過錯：** RSI 用簡單平均（`gains.sum / period`）實作，而非 Wilder's Smoothed Moving Average（EMA）。第一個 RSI 用簡單平均正確，但後續每筆應用 `(prev_avg × (n-1) + current) / n`。簡單平均會讓 RSI 在超買/超賣區域偏差，影響判斷。

**防治：**
1. 實作任何技術指標（RSI、MACD、Bollinger Bands、ATR 等）前，先查 **Investopedia** 或 **原始論文**確認算法
2. 關鍵差異：RSI 第一筆用簡單平均，後續用 Wilder's EMA（不是 SMA）
3. 實作後用已知數值（如 TradingView 同一個股同一天的 RSI）做對照驗證

**通則：** 財務計算有標準規格，不能憑直覺實作。

### 教訓 2：使用圖表函式庫前必須確認顏色衝突

**過錯：** S&R 阻力線用 `#f87171`（紅色），與 MA50 線顏色完全相同，導致使用者無法區分「四條紅色虛線」。部署前沒有做視覺對比檢查。

**防治：**
1. 同一張圖上所有視覺元素（線色、虛線、參考線）列出顏色表，確認無重複
2. 新增圖層時，用 Playwright 截圖或 browser snapshot 確認顏色可辨識
3. 顏色命名規則：MA 系列用暖色（黃/紅），S&R 用獨立冷色（橘/翠綠），RSI 用紫/藍

### 教訓 3：引入新圖表函式庫時必須先確認維度初始化 API

**過錯：** 從 Recharts（`<ResponsiveContainer width="100%">`自動處理寬度）切換到 lightweight-charts 時，忘記 lightweight-charts 需要在 `createChart()` 明確傳入 `width`，否則可能初始化為 0px。

**防治：**
1. 換函式庫前先讀官方文件的「Responsive layout / Sizing」章節
2. lightweight-charts 標準模式：`createChart(el, { width: el.offsetWidth || 600, height: N })`，再搭 `ResizeObserver` 動態更新
3. 每次初始化後用 `console.log(chart.options().width)` 或 DevTools 確認寬度非零

### 教訓 4：非同步資料切換時必須立即清除舊狀態

**過錯：** 切換 range tab 時，`setLoading(true)` 但 `data` 沒有同時清空，導致舊圖表短暫殘留（閃爍）。

**防治：** 凡是「載入新資料替換舊資料」的場景，一律同步清空舊狀態：
```typescript
setLoading(true)
setError(false)
setData([])       // ← 必須同步清空，不能等新資料才清
```
**規則：** loading=true 與 data=[] 必須同一個 tick 執行。

### 教訓 5：使用外部 Observer/Subscription 時必須處理 cleanup 競態

**過錯：** `ResizeObserver` callback 在 `useEffect` cleanup 執行後仍可能觸發，此時 chart 已被 `remove()`，導致對已銷毀物件呼叫方法。

**防治：** 凡是在 `useEffect` 內建立的 Observer/EventListener/Subscription，cleanup 時用 flag 防競態：
```typescript
let removed = false
const observer = new ResizeObserver(() => {
  if (removed) return  // ← guard
  chart.applyOptions({ width: el.offsetWidth })
})
return () => {
  removed = true       // ← 先標記
  observer.disconnect()
  chart.remove()
}
```
**通則：** React useEffect cleanup 執行時，非同步 callback 可能仍在 queue 中，必須加 guard 防止使用已清理的資源。

## 2026-04-02 — 融資試算器：四個重複性錯誤

### 教訓 1：重構變數名稱後必須 grep 確認無殘留

**過錯：** `AddPositionForm` 把 state `livePrice` 重構為 `priceInfo`，但 `useEffect` 第一行的 `setLivePrice(null)` 漏改，導致 Tab 2 整個 crash（`ReferenceError: setLivePrice is not defined`）。

**防治：**
1. 改變數名稱後立即執行 `Grep "舊名稱" app/frontend/` 確認零殘留
2. TypeScript `strict mode` + `noUncheckedIndexedAccess` 本應在編譯時抓到此錯誤 → commit 前必須確實跑 `npx tsc --noEmit`，零 error 才允許 commit

**規則：** 重構後 = grep 確認 + tsc 通過，缺一不可。

### 教訓 2：Tailwind 新 class 不保證即時生效，顏色調整直接用 inline style

**過錯：** 改容器底色 `bg-green-900` → `bg-green-800` → `bg-green-700` 截了三輪截圖都沒變，最後改用 `style={{ backgroundColor: '#166534' }}` 才生效。

**根本原因：** Vite JIT 快取、或該 class 未在其他地方使用被 purge。

**防治：** 顏色微調（尤其是不常用的 class）**直接用 inline style + hex 色碼**，避免 Tailwind purge 或快取問題浪費截圖輪迴。

### 教訓 3：CSS `overflow-hidden` 會裁掉 `absolute` 子元素

**過錯：** PriceInfoBar 的 52WK marker 設為 `absolute`，放在有 `overflow-hidden` 的父容器裡，被完全裁掉不可見，花了多次截圖才診斷出來。

**防治：**
- 需要 `absolute` 定位的子元素，父容器用 `relative`，**不加 `overflow-hidden`**
- 或把 marker 移到 `overflow-hidden` 容器之外

### 教訓 4：UI 元件修改後必須先截圖確認再 commit

**過錯：** bar 高度 `h-2` ↔ `h-3` 來回兩次，浪費 4 個 commit；PriceInfoBar 整個重寫後直接 commit，沒有截圖確認。

**防治：** CLAUDE.md 已規定「UI 修改後用 Playwright 截圖驗證」— **這是硬性要求，不是選項**。流程：
```
修改 → 截圖確認外觀正確 → commit
```
不允許「先 commit 再截圖」。

---

## 2026-04-03 — 排程、文件同步、快取模式：三個重複性陷阱

### 教訓 1：推薦新方案前必須先確認現有基礎設施模式

**過錯（2026-04-03）：** 實作 Telegram 收息提醒的排程機制時，直接建議 crontab，但專案早已用 `systemctl --user` 管理 `fairprice.service` 和 `fairprice-vite.service`。

**重複犯罪（2026-04-14）：** 同樣的錯誤再犯——使用者說「精簡 crontab」，直接改 crontab，沒有先確認已有 systemd timer（`options-collector.timer`、`options-intraday.timer`），導致同一隻腳本被 crontab 和 systemd 雙重執行。

**根本原因：** 教訓停留在原則層面（「先看有沒有 .timer」），沒有轉化為操作前強制執行的具體指令。

**強制查核 SOP（碰到排程任務必須先跑這兩行）：**
```bash
crontab -l                                        # 看既有 crontab
systemctl --user list-units --type=timer          # 看既有 systemd timer
```

**其他類型的強制查核：**
- 快取 → `grep -r "Rails.cache\|Redis\|File.write" app/services/ | head -5`
- 後台工作 → `grep -r "perform_later\|perform_async" app/ | head -5`
- 日誌格式 → `grep -r "Rails.logger" app/ | head -3`

**規則：** 任何「新增排程/快取/背景工作」任務，**查核指令必須在第一步執行，結果必須貼出來確認後才能繼續**。看到輸出才知道現有模式是什麼。

---

### 教訓 2：修改實作後必須同步搜尋並更新所有提及舊技術的文件

**過錯：** 應用早已從 Anthropic Claude API 切換到 Groq，但 `docs/ARCHITECTURE.md`、`RAILS_AUDIT_REPORT.md`、`README.md`、`config/initializers/content_security_policy.rb` 仍寫著「Anthropic Claude API / claude-opus-4-6」，直到使用者主動要求確認才一次清除。

**根本原因：** 每次修改程式碼只改了實作，沒有把「搜尋並更新相關文件」納入完成定義。

**防治：** 凡是涉及以下類型的技術替換，完成後必須執行：
```bash
grep -rn "舊技術名稱" docs/ README.md config/ app/ --include="*.md" --include="*.rb"
```
並逐一更新所有參考。技術替換的完成定義 = **程式碼改完 + 文件同步 + grep 零殘留**。

---

### 教訓 3：新增 service 時必須確認快取模式與現有程式碼一致

**過錯：** `ExchangeRateService` 用 `File.write("/tmp/...")` 做快取，而整個 app 其他 service（`OuouAnalysisService`、`FinnhubService` 等）一律用 `Rails.cache`。這個不一致在寫入時沒被察覺，直到審計才發現並修正。

**根本原因：** 讀取 service 程式碼時沒有主動比對「這個快取模式和其他 service 一樣嗎？」

**防治：**
1. 新增或審查任何 service 時，確認快取方式是否使用 `Rails.cache`（本專案標準）
2. 看到 `File.write`、`File.read` 用於快取時，立即標記為需要替換
3. `Rails.cache.fetch` 是標準寫法，兼顧讀取+寫入+TTL，一行解決：
   ```ruby
   Rails.cache.fetch("key", expires_in: 1.hour) { fetch_from_api }
   ```

---

## 2026-04-11 — WSL2 安裝程式：三個工作流程失誤

### 教訓 1：產生產出物的腳本，寫完就要執行

**過錯：** `package.sh` 寫完後直接交差，沒有執行驗證輸出。使用者必須問「為什麼我沒看到 fairprice-installer 目錄？」才發現目錄根本不存在。

**防治：** 凡是腳本的主要目的是「產生某個產出物」（目錄、檔案、tarball 等），寫完就必須執行並向使用者展示結果。不能只說「腳本已建立」就結束。

**規則：** 腳本完成 = 寫完 + 執行 + 驗證輸出存在。

---

### 教訓 2：打包腳本完成後必須驗證所有 .sh 的執行權限

**過錯：** `package.sh` 打包完成後未驗證 `bin/ouou-pre-market.sh` 的權限，實際是 644（無執行權限），直到使用者主動詢問才發現並修正。

**防治：** 任何產生可執行檔案目錄的腳本，完成後必須執行：
```bash
stat -c "%a %n" <output_dir>/**/*.sh
```
確認所有 `.sh` 均為 755 再交付。

**規則：** 打包完成 = 產出目錄存在 + 所有 .sh 為 755。

---

### 教訓 3：出計畫前必須確認所有限制條件

**過錯：** ExitPlanMode 被打回兩次：
1. 計畫寫成「修改既有 app 程式碼」，但使用者要的是「另外寫獨立安裝程式」
2. 計畫包含 GitHub clone，但使用者說不需要 GitHub

**根本原因：** 沒有把「不改現有程式碼」、「不依賴 GitHub」這類限制條件列出來確認，就直接出計畫。

**防治：** 計畫前先確認：
- 「這是改現有程式，還是新建獨立工具？」
- 「有哪些外部依賴（GitHub、網路、特定工具）不能使用？」
- 「產出物放在哪裡、以什麼形式交付？」

**規則：** 需求含糊時，先用 AskUserQuestion 釐清邊界條件，不要假設。

---

## 2026-03-25 — Storybook + Chromatic：vite-plugin-ruby 路徑污染

### 症狀
Chromatic 上傳後報 "JavaScript failed to load"。
建置出的 `iframe.html` 中，asset 路徑是 `/vite/assets/xxx.js`，但實際檔案在 `assets/`。

### 根本原因
`@storybook/builder-vite` 的 `commonConfig` 呼叫 `loadConfigFromFile`，
即使設了 `viteConfigPath: ".storybook/vite.config.ts"`，
仍然也會載入 **根目錄的 `vite.config.ts`**，把 `RubyPlugin()` 帶進 plugins 陣列。
`vite-plugin-ruby` 的 `config` hook 把 `base` 改為 `/vite/`，覆蓋了一切。

### 正確修法（雙重保險）

**1. `vite.config.ts`：環境隔離**
```ts
export default defineConfig(() => {
  const isStorybook = process.argv.some((arg: string) => arg.includes('storybook'));
  return {
    plugins: [!isStorybook && RubyPlugin()].filter(Boolean),
    base: isStorybook ? './' : undefined,
  };
});
```

**2. `.storybook/main.js`：viteFinal 備用過濾**
```js
async viteFinal(config) {
  config.plugins = (config.plugins ?? []).flat(Infinity).filter(
    (plugin) => plugin && plugin.name !== "vite-plugin-ruby" && plugin.name !== "vite-plugin-ruby:assets-manifest"
  );
  config.base = "./";
  return config;
}
```

### 偵錯方法
在 `viteFinal` 加 `console.log(allPluginNames)` 確認 `vite-plugin-ruby` 是否在場。
若在場，表示根 config 被載入；用上述兩種方法移除即可。

### 無效的嘗試（不要重試）
- 在 `.storybook/vite.config.ts` 設 `base: '/'` → 會被 sbConfig 的 `base: './'` 覆蓋
- 在 `viteFinal` 只設 `config.base = '/'` → RubyPlugin 的 config hook 之後再次覆蓋
- 清除 Storybook cache → 無效，問題不在 cache

---

## 2026-04-19 — Tippy+KaTeX tooltip、CBOE 整合：五個錯誤

### 錯誤 1：嘗試直接寫入 ~/.claude/settings.json（被系統阻斷）

**過錯：** 兩次用 Write/Edit 工具修改 `~/.claude/settings.json`，均被 Claude Code 自改保護阻斷，浪費 2 輪。

**根本原因：** Claude Code 有內建保護，禁止自己修改 `~/.claude/` 下的 JSON 設定檔。

**防治：**
- 凡需修改 `~/.claude/settings.json`（或其他 `~/.claude/` 下的 JSON），**直接告知用戶需手動執行**，給出具體指令或 Python 腳本。
- 不要嘗試用 Write / Edit / Bash 工具寫入，節省輪次。

---

### 錯誤 2：Obsidian 去重用 commit message，被 grep 過濾邏輯拆穿

**過錯：** `post-push-obsidian.sh` 用 `git log -1 --format="%s"` 取 commit message 存為去重憑證，但輸出時用 grep 過濾掉 "chore: 自動提交"，導致 state file 儲存的 subject 永遠不等於 log 輸出，每次都重複寫入。

**根本原因：** 去重憑證（業務過濾前的原始值）與去重比對點（業務過濾後的輸出）是同一欄位，一旦過濾邏輯介入就短路。

**防治：**
- 去重憑證必須用 **不受業務邏輯影響的欄位**：commit hash (`git log -1 --format="%H"`) 存入 state file。
- 邏輯順序：先 hash 比對 → 決定要不要執行 → 執行時再做過濾。

---

### 錯誤 3：用 `python3 -c "..."` 寫多行 Python，被 bash 展開破壞

**過錯：** 用 `python3 -c "content = '...'"` 寫多行 Python 腳本到檔案，bash 展開了 `${}`, backtick、雙引號，導致 SyntaxError 或邏輯錯誤。

**根本原因：** bash 雙引號 heredoc 會展開特殊字元；`-c` 字串也同理。

**防治：**
```bash
# ✅ 永遠用單引號 heredoc 寫 Python
python3 << 'PYEOF'
content = r"""
import re
pattern = r'^\d+'
"""
print(content)
PYEOF

# ❌ 禁止
python3 -c "pattern = '\d+'"
```

---

### 錯誤 4：修改 `<table>` 結構時沒數欄數，造成 thead/colgroup 不一致

**過錯：** 在 both-mode 的 thead row-1 多插了 `{!single && strikeBadgeTh}`，造成 row-1 有 14 個 `<th>` 而 row-2 只有 13 個，表格渲染錯位。

**根本原因：** 複製貼上既有行時沒有逐格計數。

**防治：**
- 修改 table 欄結構時，在改完後立即在 browser console 跑 assertion：
  ```js
  const colCount = document.querySelectorAll('colgroup col').length;
  const row2Count = document.querySelectorAll('thead tr:nth-child(2) th').length;
  console.assert(colCount === row2Count, `欄數不符: col=${colCount} th=${row2Count}`);
  ```
- 或在程式碼同一處加行 comment：`// row-1 = N cols, row-2 = N cols, colgroup = N cols`。

---

### 錯誤 5：KaTeX 字體載入中截圖 timeout，沒有偵錯提示

**過錯：** Tippy + KaTeX 字體非同步載入，`browser_take_screenshot` timeout 後靜默失敗，誤以為頁面正常。

**根本原因：** 截圖工具在字體請求未完成時 timeout，不報告具體原因。

**防治：**
- 有第三方 CSS 字體（KaTeX、Google Fonts 等）的頁面，截圖前先用：
  ```js
  browser_evaluate: document.fonts.ready.then(() => 'fonts-loaded')
  ```
  或確認關鍵 DOM 元素已存在再截圖。
- 若截圖持續 timeout，改用 `browser_evaluate` 驗證 DOM 狀態作為替代驗證手段。

---

### 錯誤 6：高輸出指令與大檔讀取未使用 RTK 前綴

**過錯：** 今日 session 中以下指令未加 `rtk` 前綴，直接消耗大量 context：
- `git log --oneline` / `git show <sha> --stat`（輸出超過 5000 行 diff）
- `cat architecture_spec.yml`、`cat 工作日誌.md`
- Read tool 讀取 `package.sh`（89 行，應用 `rtk read`）

**根本原因：** 沒有養成「每次 Bash 前先問自己：這個指令輸出量大嗎？」的反射動作。

**防治（強制清單）：**
- `git log`、`git show`、`git diff` → 一律 `rtk git ...`
- `cat <file>` → 一律 `rtk cat <file>`
- 任何 100 行以上的檔案 → 禁用 Read tool，改 `rtk read <path>`
- 記住：`rtk` 的用途是截斷輸出，保護 context window，不用是浪費 token

**代價：** 一次 `git show` 輸出 5000+ 行 = 數千個 token 白白消耗。

---

### 錯誤 7：RTK hook 無聲改寫，模型不知情無法學習

**過錯：** `rtk-rewrite.sh` v3 自動改寫 Bash 指令但不輸出任何提示，模型完全看不到改寫發生，無法建立「下次主動寫 rtk」的回饋迴路。

**根本原因：** 無聲改寫 = 安全網，但不是學習機制。模型持續犯同樣的錯誤，hook 持續代勞。

**修正（v4）：** 改寫時同時向 stderr 輸出警告：
```
⚠️  [RTK 強制] 下次請直接寫 rtk 版本，不要等 hook 代勞：
    原始: git log --oneline -10
    改為: rtk git log --oneline -10
```

**設計原則：** hook 必須讓違規行為「有感」，否則是隱形修正，永遠學不會。

---

### 錯誤 8：sed 插入字面 `\n` 而非真實換行

**過錯：** 用 `sed -i 's/old/new\n  content/'` 想插入新行，結果寫入了 `\n` 兩個字元，需要額外跑 Python 修正，多花 2 輪往返。

**根本原因：** BSD/GNU sed 的 `s///` 對 `\n` 行為不一致，且沒有事後驗證。

**防治：**
```bash
# ❌ 禁止用 sed 做多行替換
sed -i 's/old/new\n  content/' file.rb

# ✅ 一律用 Python
python3 << 'PYEOF'
content = open(path).read()
content = content.replace(old, new)
open(path, 'w').write(content)
PYEOF
# 完成後驗證
grep -n "關鍵字" file.rb
```

---

### 錯誤 9：不可逆操作（DB write）確認選項後立即執行，未等使用者二次確認

**過錯：** 使用者說「A」後立刻執行 `rails runner` 更新資料庫，使用者必須手動中斷才能改選 B。

**根本原因：** DB write / 破壞性操作屬「需確認才執行」類別，但跳過了顯示計畫的步驟。

**防治：** 凡 DB write、檔案刪除、採集觸發等不可逆操作，執行前必須顯示：
```
即將執行：<具體指令或 SQL>
確認執行？
```
等使用者明確回覆才動。選項 A/B/C 的回答只是「選方向」，不是「立刻執行」的授權。

---

### 錯誤 10：Read / Edit tool 未先用 `rtk read` 導致被 hook 封鎖

**過錯：** 兩次嘗試用內建 Read tool 讀 > 100 行檔案被封鎖；一次用 Edit tool 修改未被 Read 追蹤的檔案也被拒絕。每次都需要補救。

**防治（強制清單）：**
- 任何 `.rb` / `.tsx` / `.py` 檔 → 預設 `rtk read <path>`，不試 Read tool
- 要編輯的檔案 → 讀取後用 Python/Bash 直接修改，不用 Edit tool（除非確定 < 100 行）
- Edit tool 使用前提：必須先用 Read tool（不是 Bash）讀過

---

### 錯誤 11：違反 Graph-first rule，直接 Grep 搜尋程式碼

**過錯：** 找 options 相關程式碼全程直接 Grep，hook 警告出現 5 次以上。

**根本原因：** 沒有養成「先問 graph，graph 沒答案才用 Grep」的反射動作。

**防治：**
1. `semantic_search_nodes("關鍵字")` 先試
2. 結果為空 → 用 Grep，並記錄「此功能 graph 未覆蓋」
3. 避免同一 session 對同一功能重複嘗試 graph

---

### 錯誤 12：Shell 變數不跨 Bash tool call 存活

**過錯（2026-04-20）：** 在第一個 Bash call 設定 `FILE=/home/.../OptionsChainTable.tsx`，第二個 Bash call 直接用 `$FILE`，得到 `sed: $FILE: No such file or directory`，連犯兩次。

**根本原因：** 每個 Bash tool call 是獨立的 shell process，上一個 call 的環境變數完全消失。

**防治：**
```bash
# ❌ 禁止跨 call 使用變數
# Call 1:
FILE=/home/idarfan/fairprice/app/frontend/.../Foo.tsx
# Call 2:
sed -i 's/old/new/' $FILE   # → $FILE 是空字串

# ✅ 方案 A：同一個 call 內用完整路徑
sed -i 's/old/new/' /home/idarfan/fairprice/app/frontend/.../Foo.tsx

# ✅ 方案 B：同一個 call 內宣告並使用
FILE=/home/idarfan/fairprice/app/frontend/.../Foo.tsx && sed -i 's/old/new/' "$FILE"

# ✅ 方案 C：改用 Python（最穩，不受 shell 狀態影響）
python3 << 'PYEOF'
path = "/home/idarfan/fairprice/app/frontend/.../Foo.tsx"
...
PYEOF
```

**規則：** 需要跨多步驟操作同一個檔案，一律用 Python heredoc 或在同一個 Bash call 內完成。

---

## 2026-05-03 — IV Sidecar 遷移、假日日期、API 探索：三個錯誤

### 錯誤 13：修改 Python sidecar 後沒有告知需要重啟 pm2

**過錯：** 上次對話把 `python/iv_sidecar.py` 從 yfinance 改成 FlashAlpha surface 並 commit（`d64ec43`，16 分鐘前），但 pm2 的 `iv-sidecar` 程序是 28 分鐘前啟動的舊版本。新程式碼在磁碟上，舊程式碼在記憶體裡跑，snap 警告繼續出現。使用者回報 bug 才發現。

**根本原因：** Python 不熱重載（不像 Phlex/Rails）。修改 `.py` 後 pm2 不會自動套用，必須手動重啟。

**防治：**
```
修改任何 python/ 目錄下的 .py 檔後，完成 commit 前必須執行：
  pm2 restart iv-sidecar
  pm2 logs iv-sidecar --lines 5 --nostream   # 確認 Flask 已重新啟動
測試通過後才算完成。
```

**規則：** Python sidecar 的「完成定義」= 程式碼改完 + commit + `pm2 restart` + log 確認。少任何一步都是未完成。

---

### 錯誤 14：對使用者的日期主張直接反駁，而非先查美股假日日曆

**過錯：** 使用者說「6月12再下去一個檔期是6/18」，我根據日曆計算「6月第3個週五是6/19，6/18是週四，你錯了」並附上日曆輸出堅持己見。但使用者是對的：6/19 = Juneteenth（美國聯邦假日），NYSE 休市，月選到期日自動前移到 6/18（週四）。使用者必須截 Barchart 截圖才能讓我認錯。

**根本原因：** 只驗證「第幾個週五」，完全沒考慮美國聯邦假日會讓選擇權到期日提前。

**防治：**
1. 凡涉及美股選擇權到期日，日曆計算後還要對照美股假日清單：
   - Juneteenth（6/19）、Independence Day（7/4）、Christmas（12/25）、New Year（1/1）落在週五時，到期日**前移一天至週四**
2. 使用者有實際平台（Barchart、IB、TD）截圖支撐的主張，**不要直接反駁**，先查：
   ```bash
   python3 -c "import datetime; d=datetime.date(YYYY,M,D); print(d.strftime('%A'))"
   # 再查 US Federal holidays
   ```
3. 不確定假日時，承認「讓我查一下是否有假日調整」，而非篤定地給出錯誤答案。

---

### 錯誤 15：測試新 API key 時盲目猜測端點，浪費多輪

**過錯：** 使用者要測試 `FLASHALPHA_API_KEY`，我依序嘗試了 `api.flashalpha.ai`、`api.flashalpha.io`、`flashalpha.io`、`flashalpha.com`、`api.flashalpha.com` 等多個域名，全部失敗。最後是使用者直接提供正確指令 `curl -H "X-Api-Key: ..." https://lab.flashalpha.com/v1/...` 才解決。

**根本原因：** 沒有文件就自行猜測 API 端點，屬於無依據的試誤。

**防治：**
1. 收到新的 API key 時，**第一步**是要求使用者提供對應的 API 文件或範例指令，而不是自行猜域名。
2. 若無文件，依序嘗試：root domain → `/api/` → `/v1/` → `/health`，最多 3 次，找不到就停下來問。
3. 記住 FlashAlpha 正確端點：`lab.flashalpha.com/v1/`，Header 用 `X-Api-Key`。

---

### 錯誤 13 補充：Ruby/Rails 程式碼改完同樣需要重啟 pm2

**補充：** 今日同樣犯了 Python sidecar 那個錯誤的 Rails 版本 — 修改了 controller、routes、Phlex component，但沒有重啟 `fairprice-rails`，使用者看到的還是舊行為。

**強制 SOP（修改程式碼後的重啟清單）：**

| 改了什麼 | 需要重啟 |
|---------|---------|
| `python/*.py` | `pm2 restart iv-sidecar` |
| `app/controllers/`, `app/services/`, `config/routes.rb`, `app/components/` | `pm2 restart fairprice-rails` |
| `app/frontend/**/*.tsx` | 不需要（Vite HMR 自動熱重載）|

**規則：** 每次 commit 涉及 Ruby/Python 檔案，commit 訊息後立即執行對應重啟指令，再驗證。

---

### 錯誤 14：Phlex 2.x 封鎖 on* 事件屬性（2026-05-17）

**現象：** 在 Phlex 元件裡直接寫 `onclick: "..."` → 執行時拋出 `Phlex::ArgumentError: Unsafe attribute name detected: onclick`。

**根因：** Phlex 2.x 將所有 `on*` 事件處理屬性列為不安全（XSS 防護），呼叫時直接 raise。

**正確替代方案（依複雜度選擇）：**

| 場景 | 做法 |
|------|------|
| 純收合/展開 | 原生 `<details>/<summary>`（零 JS） |
| 簡單互動 | Stimulus controller + `data: { action: "click->..." }` |
| 頁面底部統一 | `render_scripts` 裡的 inline JS（事件綁定在此，不在元素上） |

**PostToolUse Hook 已新增：**  
`post-edit-phlex-unsafe-attrs.sh` — 修改 `app/components/**/*.rb` 後自動掃描 on* 屬性，發現即 block 並給出替代方案提示。

---

### 錯誤 15：Chart.js canvas.width（物理像素）≠ chartArea（CSS 像素）（2026-05-17）

**現象：** 用 `ivC.canvas.width - ivC.chartArea.right` 計算 `rightPad`，DPR≥1 時值正確，但 DPR=2 的螢幕上 `canvas.width` 是 CSS 寬度的 2 倍，導致 padding 被放大，Skew 圖的柱子只填一半寬度。

**根因：** `canvas.width`（HTML Canvas attribute）= 物理像素 × devicePixelRatio；`chartArea.right`（Chart.js layout）= CSS 像素。兩者不在同一座標系。

**正確做法：**
- 不要用 `canvas.width`，改用 `chart.width`（Chart.js 儲存的 CSS 寬度）
- 或改用與 CSS 像素一致的 `afterFit` 回呼讀取 `scale.width`

**最終解法：** Skew chart 加隱藏 `y2` spacer 軸，`afterFit` 裡 `scale.width = ivC.scales['y2'].width`，直接對齊，完全不需要計算 canvas 尺寸。

**規則：** Chart.js 跨圖計算尺寸時，一律用 `chart.width/height`（CSS pixels），不用 `canvas.width/height`（physical pixels）。

---

### 錯誤 16：市場資料 rake task 缺少週末 guard（2026-05-17）

**現象：** `iv:skew_snapshot` 和 `iv:daily_snapshot` 在週末也執行，往 `skew_rank_daily` 寫入無效資料（週六日美股不開盤，IV 資料無意義）。

**根因：** rake task 沒有檢查 ET 時區的星期幾。

**修正：**
```ruby
et = Time.current.in_time_zone("Eastern Time (US & Canada)")
if et.wday == 0 || et.wday == 6
  puts "[task] 週末跳過"
  next
end
```

**規則：** 任何抓取美股 IV/價格/財報資料的排程 rake task，**第一步必須加週末 guard**（用 ET 時區判斷 wday 0=日、6=六）。

---

### 錯誤 17：Controller 呼叫 Service 漏傳參數（2026-06-28）

**現象：** `/leaps?symbol=NOK&job_status=error` 出現 `wrong number of arguments (given 1, expected 2)`，`LeapsOptionsFlowPanelService.new(@symbol)` 少傳了 `ranked_candidates`。

**根因：** RSpec 只跑了 service 層的單元測試，controller 層的 `new(...)` 呼叫完全沒有測試覆蓋。在視覺截圖時也只截了空白頁（symbol 未傳），沒有帶實際資料觸發 service 初始化路徑。

**規則：** 新 controller 凡有呼叫 service 初始化，完成後**必須在瀏覽器實際帶參數走一次 end-to-end**（至少帶 `symbol=XXX` 讓 index 跑到 service 那行），不能光靠 unit spec 就宣告完成。

---

## 2026-07-03 — LEAPS 抓取誤判修復（輪詢取代固定 sleep）

**現象：** `leaps_scraper.py` 抓取 NOK strike=7.0 的 Options Prices 時，Stage 2 的 `cdp_navigate` + 固定 sleep（5000ms）後仍讀到 null。scraper 因 `null` 誤判為 session 過期，提前中止。

**根因：**
1. `bc-data-grid._data` 從 null → populated 的時間不固定，固定 sleep 不保證夠。
2. Stage 1（NTM 頁）也用固定 sleep，從其他頁切換過來時同樣可能不夠。
3. `barchart_session_expired` 作為唯一錯誤碼，掩蓋了「根本沒等夠」的真正原因。

**修復：**
- `_wait_for_grid(ws_url, js, max_wait_s, poll_s)` — 每 500ms 輪詢 cdp_eval，最多等 30s，第一個非 None 結果立即返回。
- `_confirm_empty(ws_url, js, delay_s=1.5)` — `[]` 結果等 1.5s 二次確認，排除瞬間空值。
- Stage 1（NTM）也改用 `_wait_for_grid`（原先 STAGE1_SETTLE=5000ms 固定 sleep）。
- 三分類：None（超時→partial）/ []（確認空→skip log）/ data（正常繼續）。
- `skipped_strikes` 字段記錄跳過的 strike/layer，方便診斷。
- `reason` 字段區分 `session_expired` vs `page_load_timeout`，避免誤導使用者。

**規則：**
1. **凡 Angular grid 取資料，必須輪詢，不能固定 sleep。** `_data` 過渡時間不穩定。
2. **Stage 1 也受影響。** 從不同 URL 切換到 NTM 頁，同樣需要輪詢等待。
3. **Unit tests 的 wait_side mock 必須按 JS 內容路由：** `"itmProbability" in js` → VG；`"bidPrice" in js` → Stage 2 opts；其餘 → Stage 1 NEAR_MONEY。不能按呼叫順序路由（Stage 1 改用 polling 後順序改變）。
4. **測試 fixture 的 key 名稱必須用 JS 映射後的名稱**（`strike`/`dte`/`bid` 等），不能用 Barchart 原始欄位名（`strikePrice`/`daysToExpiration` 等）。

## 2026-07-04：migration 後必須重啟 dev server 再跑 E2E

pm2 上長駐的 Rails process 在 migration 前啟動，ActiveRecord schema cache 沒有新欄位，
`insert_all` 帶新欄位 key 直接 raise → transaction ROLLBACK。dev 模式的 code reload
不會刷新 connection 的 schema cache。

**規則**：跑完 `rails db:migrate` 之後、跑任何走 server 的 E2E 之前，先徵求同意重啟
`pm2 restart fairprice-rails`（注意 process 名稱是 `fairprice-rails`，不是 `fairprice`）。
症狀特徵：測試環境全過但 server E2E 失敗 + log 有 ROLLBACK 無明顯錯誤（錯誤被 job rescue
吞進 memory cache，跨 process 讀不到）。

## 2026-07-05：propshaft load path 在 boot 時固定

新增 asset 目錄（如 `vendor/assets/javascripts/`）後，執行中的 server 不會看到它——
propshaft 的 load path 在 boot 時決定，dev code reload 不會刷新。症狀：rails runner
驗證路徑存在（新 process）但頁面 `Propshaft::MissingAssetError`（舊 process）。
**規則**：新增 asset「目錄」後必須重啟 server；且不要用 rails runner 驗證執行中
server 的狀態——runner 是新 process，結論不適用（schema cache 教訓的同型錯誤）。

## 2026-07-05：html-to-image 匯出 overflow 容器要無條件展開

clone 在 SVG foreignObject 內字體度量與 live DOM 略異：live 無溢出的容器在 clone
內可能溢出幾 px，捲軸就被畫進輸出、蓋住最後一列。匯出前對所有 overflow:auto/scroll
容器無條件暫改 visible（不能只看 live 量測），完成後還原。

## 2026-07-08：Barchart 近期到期日 ≠ LEAPS 到期日的履約價階梯

`?moneyness=10` 不帶 `expiration=` 參數時，Barchart 預設載入**最近**到期日（如週選），
不是遠期 LEAPS。近期到期日與遠期 LEAPS 的履約價階梯是**不同的集合**——深度價內/價外
的間距、存在與否都可能不同（NOK 實測：週選鏈 $6/7/8/8.5/9…16.5，2028-01-21 LEAPS
鏈 $2/2.5/3/3.5/4/4.5/5/5.5/7/10/12/15/17/20/22/25/27/30/32）。

**規則**：任何要驗證/引用「LEAPS 履約價鏈」的邏輯，必須明確導航到 DTE>=364 的到期日
去抓履約價清單，不能用預設（近期）到期日的清單當作 LEAPS 履約價的真值來源。
`moneyness=100`（或更高）在單一到期日下會回傳該到期日完整履約價階梯（更高值不再
增加，已驗證平頂），可用來一次拿到某到期日的完整清單。

## 2026-07-08（補充）：字型子集「內容變更」（檔名不變）也要重啟

先前記錄的教訓是「新增 asset 目錄/檔案後必須重啟」；這次證實同一份既有字型
檔案（檔名不變，只是 subset 內容更新、bytes 改變）propshaft 也需要重啟才會
產生正確的新 digest。凡是重跑 subset_font.sh／subset_ipa_font.sh 之後，
即使檔名沒變，都要當作「新增資產」處理，先徵求同意再重啟。


## 2026-07-09：user_strike 換了、但 fresh 快取只看時間不看涵蓋範圍

`fresh_data_exists?` 只檢查 `LeapsOptionChainSnapshot.fresh`（scraped_at 在
FRESH_WINDOW 內），完全沒檢查這批候選是否落在**這次**請求的 user_strike 附近。
症狀（NOK 實測）：先查過一次（自動偵測或別的履約價，中心落在 $12），30 分鐘內
換輸入履約價 7 重查，系統誤判為 cache hit，畫面顯示的還是 $12 那組候選，
跟輸入的 7 完全無關——不是 UI bug，是 controller 快取判斷的邏輯漏洞。

**規則**：`fresh_data_exists?` 帶 user_strike 時，必須額外檢查 fresh scope 內
是否有履約價落在 user_strike ± buffer（buffer = max(20%, $1)，呼應
`leaps_scraper.py` Stage 1「中心履約價 ±1 檔」的設計）；沒有涵蓋到就當 cache
miss，強制用新的中心履約價重新爬取。同時 `LeapsRankingService`／
`LeapsRecommendationService` 本身仍不篩 user_strike——它們依賴 persist 層
（`persist_leaps` 每次 delete_all 舊資料）已經把資料窄化到新中心附近，
篩選履約價這件事實際發生在爬蟲 Stage 1，不是排行層。


## 2026-07-09（補充）：cache 判斷要看「查詢中心點是否吻合」，不是「涵蓋範圍」

上一條教訓的第一版修法用「user_strike ± 緩衝範圍」去檢查 fresh 候選是否涵蓋——
不夠精準：使用者接著追問「NOK 不帶履約價時，不是該列出最適宜的價格嗎？」才發現
對稱的反向案例——手動查過履約價 7 之後，30 分鐘內留空重查（auto 模式），系統一樣
誤判為 cache hit，沿用手動模式窄化過的 6/7/8 candidates，而不是重新做 auto 偵測。

**正確設計**：不用緩衝範圍猜，而是把「這批候選是為哪個中心點爬的」直接記錄下來——
`strike_chain_snapshots.last_query_strike`（nil＝auto 模式，數值＝手動履約價），
`persist_chain_snapshot(data, user_strike:)` 在爬蟲成功/partial 時寫入；
`LeapsOptionChainSnapshot.fresh_for?(symbol, user_strike:)` 同時比對「時間新鮮」
與「這次要求的 user_strike（nil-safe）是否等於上次記錄的中心點」，兩者都要吻合
才算 cache hit。`invalid_strike` 分支（只驗證、沒有實際重新爬）不會更新
last_query_strike，因為候選本身沒變。

**規則**：這個判斷邏輯只能有一個權威定義（在 model 的 class method），controller
的 fresh_data_exists? 與 service fetch_leaps 內部的 cache 短路都必須呼叫同一個
方法，不能各自維護一份緩衝公式或涵蓋範圍猜測邏輯。


## 2026-07-09（三）：Stage 1 auto 偵測用近期 Delta 判斷，深度價內合約常年被誤排除

使用者追問「NOK 留空查詢，7 這檔明明前面手動查時 Delta 0.85+，為什麼 auto 偵測
沒抓到？」才發現：`_pick_candidates`（leaps_scraper.py）auto 模式用「Near the
Money 視圖」（預設抓最近到期日）的 Delta 判斷候選履約價（Delta>=0.60），但
Barchart 對「近期到期日 + 深度價內 + 近期無成交」的合約常常根本不計算 Greeks，
delta/iv 兩者都回傳 0——不是「Delta 真的低於 0.60」，是「Delta 沒被算出來」。
NOK 履約價 7 在 2026-07-10（DTE 2）這個最近到期日 delta=0.0、iv=0.0，因此
auto 偵測完全跳過它，即使同一履約價在 LEAPS 到期日（DTE 562）Delta 高達 0.851。

**規則**：`_pick_candidates` auto 模式判斷候選時，delta 為 0 且 iv 也為 0
（雙零＝Greeks 未計算的訊號，非「合約沒有方向性」）時，改用內在價值判斷
（履約價 < 現價即代表 Call 為價內，理當視為候選），不能單純看 delta>=0.60
一刀切；delta/iv 任一非零仍照原邏輯（代表 Greeks 有算，且確實偏低就該排除）。

**教訓延伸**：這是繼 2026-07-08「近期到期日 ≠ LEAPS 到期日的履約價階梯」之後
第二個「近期到期日資料品質/存在性不能直接當作 LEAPS 判斷依據」的具體案例，
往後任何借用近期到期日資料做 LEAPS 決策的邏輯，都要先確認資料本身在深度
價內/價外、近期無成交的情境下是否可靠，不能預設 Greeks 一定有算。


## 2026-07-11：Phase 子規格獨立成檔後，主 spec 頂層索引沒同步更新

使用者要求審視 `leaps-call-recommendation-spec.md` 是否已納入
`leaps-phase-j-vector-pdf-spec.md`（PDF 向量文字化）已完成的階段，查證後發現：
Phase J 規格內要求的「撤銷主 spec 兩條舊規格」（PDF 先轉 PNG 再嵌入／PNG 與 PDF
畫面一致）本身確實做了（該節內文有刪除線＋「已被 Phase J 取代」註記），但主
spec 的**頂層摘要句**（「接手前必讀」）與**階段索引**（「執行方式」段落開頭）
仍然只列到 Phase I，完全沒提 Phase J 其實已經全部結案（核心 6 項＋驗收 7 項
＋4 輪補做皆附證據完成）。新 session 若只讀「接手前必讀」（規格文件本身要求
的閱讀順序），會誤判 Phase J 還沒開始，得額外去翻子規格檔進度追蹤區才發現
真相。

同一次追問還發現：主 spec「路由與前端」節只寫了「要加進導覽選單」這條**原則
性指示**，沒有記錄 LEAPS 頁面在 sidebar 的**實際交付位置**（`APP_LINKS` 陣列
第幾項、icon/label/href/desc 內容）——原則指示長期有效，但已交付事實會隨程式
異動而與規格脫節，兩者性質不同，該分開記錄。

**規則**：
1. 每完成一個獨立 Phase 子規格（Phase 有自己的檔案，例如 `leaps-phase-j-*.md`），
   除了子規格自身的進度追蹤區要更新，**必須回頭檢查主 spec 的頂層摘要句／階段
   索引是否同步列入**，不能假設「子規格裡有寫」等於「主 spec 讀者看得到」。
2. 規格文件裡「原則性指示」（例如「要加進導覽選單」）與「已交付事實」（實際
   加在哪個位置、什麼內容）應分開記錄成兩行；前者是規則、後者是快照，快照
   隨程式改動需要人工回來同步，不能省略。

**適用範圍**：不限 LEAPS，任何本專案用「主 spec ＋ Phase 子規格檔」模式管理的
功能規格，新增或結案一個 Phase 後都要照這兩條規則檢查主 spec。


## 2026-08-10：推薦分析「近期無成交」誤把相對排名當字面判斷，還拿來做排除

使用者質疑 `/leaps?symbol=NOK` 的「推薦分析」卡片挑出 OI 387 的候選，跟下方
候選排行表（依 OI 全域排序，OI 12,847/4,717/2,749... 一路遞減）完全對不上，
根本不是「按 OI 排序」也不是「前幾大」。

查證後發現兩個疊加的問題：

1. **`no_recent_volume_warning`（顯示為「近期無成交」）的判斷本身就會誤導**：
   `LeapsRankingService#low_vol_oi?` 是用 `Volume ÷ OI` 比值在本次查詢候選池
   中的**後 1/3 分位**來判斷，不是字面上的「Volume = 0」。OI 12,847、
   Volume 48 這種合約，因為分母（OI）太大，比值排到後段，一樣會被標成
   「近期無成交」——但它明明有 48 口成交，標籤文字跟實際判斷邏輯脫節。
2. **`LeapsRecommendationService#recommend_group` 拿這個有誤導性的警示去做
   `reject` 排除**：只要不是「全部候選都警示」，就把所有警示候選整批剔除，
   只在剩下的「乾淨」候選裡比 OI/流動性 tier。於是 OI 12,847/4,717/2,749/
   1,233 這些高 OI 但被誤標「近期無成交」的候選全部出局，只剩 OI 387 那筆
   去比，`build_reason` 卻寫「為此天期區間最高」，讀起來就像整體最高，跟
   候選表一比自然像是排序邏輯錯了。

**規則**：
1. 任何「相對排名／百分位」算出來的警示標籤，命名跟文案都要照實反映計算
   方式（例如改叫「Volume/OI 比率偏低」而不是「近期無成交」），不能用聽起來
   像絕對事實的字眼包裝一個相對排名的結果。
2. 這類警示標籤是「提醒使用者自行評估」的資訊，**不該被拿去當篩選/排除條件**
   （尤其當警示本身的判斷方式已經有誤導風險時），只能附註顯示在被選中的
   候選上，不能讓它默默改變誰被選中。
3. 已修正：`LeapsRecommendationService#recommend_group` 拿掉 `reject` 排除，
   純粹依 `liquidity_tier` + OI 排序（跟候選排行表邏輯一致）；警示改成
   `build_reason` 裡對 `pick` 本身的資訊性提示，並把文案改成「Volume/OI
   比率偏低」，不再用「近期無成交」字面誤導。

**適用範圍**：本專案任何用百分位/相對排名算出來的「異常/警示」欄位（不只
LEAPS，Options Flow 等其他頁面若有類似「相對排名當警示」的設計也要比照檢查：
(a) 文案是否照實反映計算方式，(b) 有沒有被拿去做篩選而非單純展示）。

## 拆分大型 Phlex component 為多個 mixin module 時的常數作用域陷阱

`leaps_recommendations/page_component.rb`（2417 行）拆成 12 個檔案時踩到的坑：

1. **Ruby bare 常數查找是 lexical scope，不是 method dispatch**：把方法搬進
   `module LeapsRecommendations::Xxx` 這種 mixin 完全沒問題（`include` 後透過
   `self` 動態派發，哪個 mixin 定義的都找得到）；但方法內部直接寫的裸常數
   （如 `LIQUIDITY_STYLE[tier]`）只會依照**該方法被定義時所在的 module 的
   lexical nesting + 該 module 自己的 ancestors** 去找，不會管最終被 include
   進哪個 class。如果 `LIQUIDITY_STYLE` 定義在 A module，卻被 B module 裡的
   方法引用，會直接 `uninitialized constant`，`ruby -c` 語法檢查完全抓不到，
   要實際 `bundle exec rails runner` 載入 class 才會炸出來。
   **解法**：把跨 module 被引用的常數抽進一個共用 module（如
   `SharedConstants`），所有需要的 module 各自 `include SharedConstants`。
2. **繼承鏈上的常數同理失效**：原本 `class PageComponent < ApplicationComponent`
   能直接用父類別常數 `SIGNAL_COLORS`；搬進不繼承 `ApplicationComponent` 的
   plain module 後要改成完整路徑 `ApplicationComponent::SIGNAL_COLORS`。
3. **拆檔前先跑一次「常數被誰引用」的全文盤點**（`grep -n <CONST_NAME>` 逐一
   看使用處是否跨越預定的拆分邊界），比事後除錯快得多。
4. **Propshaft 有 precompile 過的 `public/assets/.manifest.json` 時**，新增
   asset 檔即使實際存在於 `app/assets/javascripts/`，`javascript_include_tag`
   仍會噴 `MissingAssetError`——manifest 存在時優先查 manifest 而非即時掃描
   來源目錄，新增/搬移 JS 資產後一定要重跑 `assets:precompile`。
5. **靜態 JS 從 inline `<script>`（原本墊在 body 尾端）搬到 `<head>` 的
   `javascript_include_tag` 時要加 `defer: true`**：這些 script 若寫成「立即
   執行、假設 DOM 已建好」（例如 `document.getElementById` 沒包
   `DOMContentLoaded`），純粹是靠原本放在 body 尾端才恰好能動；搬進 head 不加
   defer 會提前執行、抓不到還沒渲染的元素、silently 失效。

## 2026-08-28 — 稽核修正

1. **稽核前先確認測試環境真的是隔離的**。`.env` 的 `DATABASE_URL` 寫死指向
   `fairprice_development`，dotenv-rails 在 test 環境同樣會載入 `.env`，
   `DATABASE_URL` 會壓過 `database.yml` 的 `database:` key —— 整套 RSpec 一直
   跑在正式資料上。症狀是「時好時壞、期望空集合卻拿到資料」的假失敗（13 個失敗中
   有 8 個是這樣來的），也代表任何「測試全綠」的結論在修好之前都不可信。
   **檢查方式**：`RAILS_ENV=test rails runner 'puts ActiveRecord::Base.connection_db_config.database'`。
   **解法**：在 `database.yml` 的 test 區塊明確寫 `url:`（唯一能穩定壓過
   `DATABASE_URL` 的方式），而且要寫在版控檔案裡，不要放 `.env.test`
   ——`.env*` 被 gitignore，新環境 checkout 後會無聲消失。

2. **`config.assume_ssl` 不是「告訴 Rails 前面有 TLS 代理」而是「無條件把每個請求
   當成 https」**。開了之後 `http://localhost:3003` 的 `redirect_to` 也會產生
   `https://localhost:3003/...`，本機沒有 TLS 監聽器，瀏覽與 Playwright 全壞。
   Cloudflare Tunnel（cloudflared）本來就會送 `X-Forwarded-Proto: https`，
   **不開 `assume_ssl`、只開 `force_ssl` + localhost exclude 才是對的**，
   Rails 會依 header 判斷，公網 https、本機 http 兩邊都正確。
   另外 `ssl_options` 的 `exclude` **管不到 HSTS header**，HSTS 會照送給 localhost
   把瀏覽器對 localhost 的 http 存取永久鎖死 —— 要 `hsts: false`，交給 Cloudflare 端設定。

3. **`ssl_options[:redirect][:exclude]` 同時控制「導向」與「Secure cookie 標記」**
   （`ActionDispatch::SSL#call` 兩個分支都會呼叫 `@exclude`），所以 exclude 掉
   localhost 之後本機登入不會因為拿到 Secure cookie 而失效。

4. **在 Ruby 裡用「最後一行 `import` 之後插入」來加 TS import 會炸掉多行 import**。
   `import type {\n  A,\n  B,\n} from './types'` 的第一行也是 `import ` 開頭，
   插進去就變成語法錯誤，而且 `rspec` 會以 `Vite Ruby can't find entrypoints/...
   in the manifests` 的形式報錯，跟真正的原因（esbuild transform 失敗）完全對不上。
   **改動前端後一定要跑 `bundle exec vite build` 確認建置通過**，再去看 RSpec。

5. **加 `user_id` 歸屬前先分清楚「個人資料」與「共用市場資料」**。
   `TrackedTicker` 驅動夜間爬蟲、產出 79 萬列共用 `OptionSnapshot`；
   `WatchlistItem` 是排程 Telegram 盤前報告的來源。這類表加 user_id 會讓
   排程作業不知道該用誰的清單，是錯的。判斷方法：**先查這張表被哪些排程／
   背景服務讀取**（不是只看 controller），有排程讀取的通常就是共用資料。

6. **加 `belongs_to :user` 之後要一併檢查 `position` 這類「流水號」欄位**：
   `self.class.maximum(:position)` 必須改成 `user.xxx.maximum(:position)`，
   否則新使用者的第一筆會拿到別人的序號。同理 factory 要加 `user`，
   而 request spec 建資料時必須掛在「自動登入的那個使用者」身上
   （已在 `spec/support/auth_helpers.rb` 提供 `signed_in_user`）。

7. **`protected_environments` 看的是「資料庫裡存的標記」，不是你下的 `RAILS_ENV`**。
   標記存在 `ar_internal_metadata.environment`，而且**會被 `db:migrate` 寫成當下的
   `RAILS_ENV`**。所以 dev 與 prod 共用同一個庫時，只保護 `production` 是不夠的
   ——隨手跑一次不帶 `RAILS_ENV` 的 `db:migrate` 就會把標記翻成 `development`，
   `db:drop` / `db:reset` 從此暢行無阻。共用庫的正解是
   `config.active_record.protected_environments = %w[production development]`。
   **檢查方式**：
   `rails runner 'puts ActiveRecord::Base.connection.pool.internal_metadata[:environment]'`。

8. **要不要把一張表分給每個使用者，看的是「下游蒐集結果怎麼 key」**，
   不是那張表本身有幾列。`iv_watchlists` 只有 6 列但下游
   （`iv_daily_snapshots` / `skew_rank_*`）是 ticker-keyed，一個代號一份快照，
   分人很便宜；`tracked_tickers` 同樣只有 6 列，但 `option_snapshots` 綁的是
   `tracked_ticker_id` 且有 80 萬列，兩個人追同一個代號就會變成兩份，
   要先把下游改成 symbol-keyed 才有辦法分。
   **判斷順序**：先查排程讀誰 → 再查下游資料表的識別欄位是 symbol 還是 FK。

9. **加 `user_id` 時，原本 `symbol` 的全站 unique index 必須改成
   `[user_id, symbol]`**，否則第二個使用者連加入同一個代號都會被擋，
   而且這個錯誤在只有一個使用者的環境（backfill 之後）完全不會出現。

10. **排程作業改用「所有使用者的聯集」時，要驗證聯集後的集合跟修改前一樣**。
    既有資料全部 backfill 給 admin 的話兩者必然相等，跑一次
    `OuouPreMarketService.new.send(:watchlist_symbols).size` 對照修改前的數字，
    就能證明排程行為沒有回歸。

11. **內嵌 JS 的行數跟 RubyCritic 的 F 級評分無關**。flog / reek 量的是 Ruby 複雜度，
    heredoc 不論裡面塞幾行 JavaScript，對 Ruby 來說就是一個字串字面值。
    反證：`IvAnalysis::PageComponent` 有 721 行內嵌 JS，評分卻是 B / cx=28.1；
    搬走 464 行之後 `education_component` 只從 964.1 降到 956.5。
    **F 級來自 Phlex 巢狀 markup，不是內嵌的 JS**——稽核報告曾把兩者混為一談，已勘誤。
    搬遷 JS 的正當理由是 ESLint／型別檢查／source map／打包／可測試／CSP，不是評分。

12. **從 Ruby heredoc 擷取 JavaScript 必須用 Ruby 求值，不能純文字複製**。
    unquoted heredoc（`<<~JS`）會先處理反斜線跳脫：`'\\n'` 在輸出的 JS 裡是換行跳脫、
    `/\\d+/` 是 `\d`、`−` 是「−」。直接複製檔案內容會全部多一層反斜線。
    正確做法：`eval(%(<<~JS\n#{body}\nJS))`；quoted heredoc（`<<~'JS'`）才可以逐字複製。
    先用 `grep '\\'` 找出受影響的行（本次 14 行）再決定怎麼處理。

13. **ESLint 沒有宣告瀏覽器全域時，`no-undef` 會把 `document` / `window` / `fetch`
    全部判成錯誤**——本專案原本 20 個「錯誤」裡全部是這種假陽性，等於 lint 形同虛設，
    真正的錯誤被淹沒。修好之後立刻浮出 4 個真錯誤。
    檢查方式：看 lint 錯誤是不是集中在 `no-undef` 且對象都是瀏覽器內建物件。

14. **把 inline `<script>` 改成 ES module 時，注意兩個作用域差異**：
    (a) 同一頁多個 inline script 共享全域作用域，拆成獨立模組後互相看不見——
        搬遷前要先檢查跨 script 的函式引用；
    (b) `window.foo = fn` 之後用 bare `foo()` 呼叫，在 module 裡**仍然有效**
        （全域物件屬性還在作用域鏈上），但 ESLint 靜態分析看不到，會報 no-undef。
        改寫成 `window.foo()` 語意相同且更清楚。

15. **`dataset` 只能給字串**，所以把 Ruby 值傳進 JS 時，`nil` 會變成空字串、
    數字會變成字串，truthiness 與型別都會改變。原本 `#{@expiration.to_json}`
    在 JS 裡是 `null`，改成 `root.dataset.expiration` 就變成 `""`——雖然同樣 falsy，
    但 `typeof` 與 `=== null` 的判斷會不同。**傳多個值或需要保留型別時，
    用單一 `data-config` JSON + `JSON.parse` 才安全。**

16. **把 `#{route_path}` 從單引號字串裡抽出來時，用 `' + CFG.routes.x + '` 取代整個
    `#{...}`**，這樣 `'#{a_path}?job_id='` 會變成合法的 `'' + CFG.routes.x + '?job_id='`，
    再用 regex 清掉多餘的 `'' +` 即可。比逐處判斷「在不在引號內」可靠得多。
    清完務必用 `node --check` 驗證語法。

17. **CSP 要真正防 XSS，`script-src` 就不能有 `unsafe_inline`**。必須先把所有 inline
    `<script>` 清光；剩下那些「必須在繪製前執行」的（例如還原字級、避免閃動），
    用 `javascript_tag nonce: true` +
    `config.content_security_policy_nonce_generator` 放行。
    **前提是專案沒有 fragment cache**——快取到舊 nonce 會讓那段 script 被擋掉。
    `style-src` 的 `unsafe_inline` 是另一回事，Phlex/Tailwind 的 inline style 拿不掉。

## 2026-08-29 — H-3 瀏覽器驗證：三個教訓

### 教訓 1：「搬遷完成」不等於「驗證完成」，載入成功也不等於功能正常

H-3 搬完 30 個 behavior、RSpec 全綠、tsc/ESLint 零錯，但其中 26 個在登入閘門後面，
當下一個都沒在瀏覽器跑過。實際登入後逐頁驗，才發現兩件靜態檢查抓不到的事：

1. `alert-dismiss` 在正式站**從來不會渲染**——`AlertComponent` 的 `dismissible`
   預設 false，所有呼叫端都沒傳 true（只有 Lookbook preview 會）。
   `behavior_registry_spec` 掃原始碼看到 `behavior: "alert-dismiss"` 就算通過，
   但那是「原始碼裡有」，不是「執行時會渲染」。
2. 字級白名單漂移（見教訓 2）。

**規則**：behavior/前端行為搬遷後，驗證要分三層，缺一層就不算完成——
chunk 以 200 載入 → 掛載點在真實頁面上存在 → 實際觸發互動看到預期結果。

**驗證手法**（可重複使用）：marker → chunk 名可由 kebab→camel 推導，不必手抄註冊表，
再比對 `performance.getEntriesByType('resource')` 裡有沒有對應的 `/assets/<camel>-` 檔。

要驗需要資料才渲染的元件（如 `tech-dash-options-charts` 要有 max_pain 快照），
先查 DB 找歷史上有資料的 symbol + date，用 query string 直接進去，不必重跑抓取。

### 教訓 2：同一份設定寫死在兩個地方，遲早會漂移

`FontSizeControlsComponent::SIZES` 是 18–22px，layout 裡還原字級的 inline script
白名單卻是 `['14','15','16','17','18']`——交集只有 `18`，使用者選 19–22 換頁後
字級被靜靜打回預設，沒有任何錯誤訊息。這在 H-3 之前就存在。

**規則**：inline script 無法 import，但**可以用 ERB 從 Ruby 常數插值**。
需要在 layout 的 inline script 裡用到某個清單/key 時，一律寫成
`var ALLOWED = <%= SomeComponent.allowed_sizes.to_json.html_safe %>;`
而不是手抄一份。前端模組同理——改從 data attribute 吃，不要自己再寫死一份。

**偵測方式**：這種 bug 不會拋錯，只能靠「改設定 → 換頁 → 確認還在」的往返測試抓到。
凡是有持久化（localStorage / cookie / session）的 UI 設定，驗收一定要含換頁往返。

### 教訓 3：`<script type="application/json">` 不是 inline script，別誤判 CSP

盤點 inline script 時用 `document.querySelectorAll('script:not([src])')`
會把資料島一起算進去。`/leaps` 因此被我誤報成「2 段 inline script、其中一段沒有 nonce」。

非可執行 type（`application/json`、`text/template` 等）不受 `script-src` 管轄，
本來就不需要 nonce。正確的過濾條件是 type 為空字串、含 `javascript`、或等於 `module`。

## 2026-08-29（二）— 「原始碼裡有」不等於「執行時到得了」

同一天挖出兩個同構的死碼，成因都是**條件的上游把路堵死了，而條件本身看起來很合理**：

| 死碼 | 上游把路堵死的東西 |
|---|---|
| `AlertComponent` 的 ✕ 與 `alert-dismiss` | `dismissible` 預設 false，5 個呼叫端沒人傳 true |
| `ValuationsController#validate_ticker` | 路由 `TICKER_CONSTRAINT` 與它的正規表示式等價，不合法代號先被 404 |

兩者都通過既有測試——`behavior_registry_spec` 掃原始碼看到字串就算過，
`validate_ticker` 則根本沒有測試。

**規則**：寫「防呆 / 錯誤處理 / 可選 UI」時，一定要問一句**「這條路真的走得到嗎？」**
並用可執行的方式證明，而不是讀程式碼推論。兩個好用的證明手法：

```ruby
# 路由到底收不收這個輸入（比讀 constraint 正規表示式可靠）
Rails.application.routes.recognize_path("/valuations/BRK.B")
```

用 Grep tool 搜 keyword argument 的實際傳值，確認有沒有呼叫端真的開啟這個選項。
本例中 `dismissible: true` 只出現在 Lookbook preview，等於正式站永遠不渲染。

**寫測試時的連帶陷阱**：我第一版測試就是拿 `/valuations/!!!` 去打 `validate_ticker`，
吃到 404 才發現那條路不通。**測試失敗有時不是程式錯，是你以為的執行路徑不存在**——
這種時候要先確認路徑，不要急著改斷言去迎合結果。

**放寬路由 constraint 的連帶效應**：`get "valuations/:ticker"` 的 constraint 原本含
`.`，剛好讓 `BRK.B` 不被切成 `ticker=BRK, format=B`。改成 `%r{[^/]{1,64}}` 之後
必須補 `format: false`，否則含小數點的代號全掛。這種事只能靠實測，不能靠讀 code。


## 2026-08-29（三）— 死碼普查：兩類「原始碼裡有、執行時到不了」

把前兩則教訓的偵測方式掃過整個 codebase，一次找出 7 處。方法可重複使用：

### 掃法 1：預設關閉的布林 keyword argument

抓出所有 `def foo(..., bar: false, ...)`，再統計正式碼裡 `bar: true` 與
`bar: <變數>` 各出現幾次。兩者都是 0 = 這個分支永遠不會執行。

12 個候選裡命中 2 個（`show_formulas`、`show_search_in_nav`）。

**關鍵區分**：`show_formulas` 的呼叫端是**明確傳 `false`**，那是刻意關閉，
不是疏漏——不要一律翻成 true。只有「沒有任何呼叫端提到過這個參數」才算死碼。

### 掃法 2：正式碼零呼叫端的元件

列出所有 `class X < ApplicationComponent`，再到 `app/**/*.{rb,erb}` 找
`X.new`。命中 3 個（171 行），全部只剩 Lookbook preview 在引用。

`ApplicationComponent` 本身會被誤判（它是被繼承而不是被 `.new`），要排除基底類別。

**額外訊號**：`log/development.log` 裡搜元件名。`PageLayoutComponent` 留有
`undefined method 'stylesheet_link_tag'` 的例外——它不只沒人用，最後一次被渲染
時就已經壞了。舊 log 是判斷「這東西是被取代還是被遺忘」的好證據。

### 掃法 3：讓 ESLint 真的跑得動

`npx eslint .` 原本吐出兩萬多則來自 `storybook-static/`、`vendor/assets/`、
`venv/` 的雜訊。**一個沒人跑得動的 lint 閘門等同不存在**——這本身就是同一類問題。

先補建置產物的 ignores 讓訊號浮出來，再處理剩下的 error。修好之後 ESLint 立刻
抓到兩處我讀 code 沒看出來的死碼：

- `no-redeclare` → `bullPutSpreads.js` 有兩個 `runCalculate()`。函式宣告會提升，
  **後面那份永遠覆蓋前面**，前面那份從未執行
- `no-useless-assignment` → 先算一次、下面必定覆寫的變數

**注意**：`(cond) ? '' : ''` 這種兩邊相同的三元運算子 ESLint 不會抓（它是合法的
賦值運算式）。要靠「這個 data attribute 有沒有人讀」反查。

### 修完之後必須重驗

我改的兩支 behavior 先前都驗過，改完必須重跑一次完整流程——`/bpus` 走到選擇權鏈
→ 選腳 → 試算 → 改口數重繪（重繪成功才證明 `lastCalcResult` 有寫入，也就是存活
的那份 `runCalculate` 確實是正確的那份）。

**量測陷阱**：用 `innerText` 判斷結果區塊是不是空的會誤判——元素在未展開的容器裡
時 `innerText` 回傳空字串。要用 `innerHTML` 或 `getBoundingClientRect` 交叉確認，
不然會把「已經正常渲染」讀成「壞掉了」。


## 2026-08-29（四）— code-review-graph MCP：整場沒用，事後實測發現該怎麼用

### 流程失誤

`CLAUDE.md` 寫得很明確：**探索程式碼一律先用 code-review-graph MCP，Grep/Glob/Read
只在 graph 覆蓋不到時才退回**。這次從稽核到死碼普查，我一次都沒用過，全程 python
讀檔 + 自己寫掃描腳本。每次 `Read` 都跳 `⚠️ GRAPH-FIRST RULE` 提醒，我一直略過。

規則本身寫的是「graph 覆蓋不到時才退回」——**我從來沒花一次呼叫去確認它覆不覆蓋
得到**，直接跳過。這才是真正的問題，不是「沒用工具」。

### 事後實測：這個 graph 對 Rails 的實際能力

事後補跑，結果不是單純的「早該用」：

**`refactor_tool mode=dead_code` 對 Rails 幾乎不能用。**
回傳 194 個「死碼」類別，裡面包含 `ApplicationRecord`、`ApplicationJob`、
`MarginController`、`OptionsController`、`OwnershipSnapshot`、`PriceAlert`……
全都是活的。原因是 Rails 大量靠慣例隱式實例化（controller 由路由按名字找、model
由 ActiveRecord 驅動），靜態呼叫分析看不到那些邊。這一輪如果照它的清單刪，會直接
把專案刪爆。

**parser 看不懂 `class A::B` 這種緊湊命名空間寫法。**（2026-08-29 追加查證後更正）

`semantic_search_nodes` 找 `WatchlistManagerComponent`（確實存在、`/momentum`
上正在用）回傳 0 筆，`callers_of` 也 `not_found`。但 `file_summary` 指到那個檔案
路徑正常回傳 8 個節點——1 個 File + 7 個 Function，**沒有 Class 節點**，而且每個
Function 的 `parent_name` 都是 `null`、`edges` 是空的。

直接查 `.code-review-graph/graph.db` 量化，結果非常乾淨：

| 宣告寫法 | 檔案數 | 有 Class 節點 |
|---|---|---|
| `class DailyMomentum::WatchlistManagerComponent` | 64 | **2**（缺 62）|
| `module DailyMomentum` + `class MarketStancePresenter` | 19 | 19（全中）|

→ **不是「巢狀命名空間不可靠」，剛好相反**：巢狀寫法 100% 正常，緊湊寫法
`class A::B` 幾乎全軍覆沒。本專案的 Phlex 元件絕大多數是緊湊寫法，所以整批在
graph 裡沒有類別層級的資訊，也就沒有 `callers_of` / `inheritors_of` 可查。

這是 tree-sitter Ruby query 的覆蓋缺口，**不是版本過舊**：實測安裝的是
`code-review-graph 2.3.8`，就是 PyPI 上的最新版（2026-08-21 發布）。
`uvx code-review-graph --version` 可自行確認。

**根因（AST 層級確認）**：tree-sitter-ruby 對兩種寫法的 `name` field 型別不同——
`class Foo::Bar` 是 `scope_resolution`，`module Foo` + `class Bar` 是 `constant`。
`parser.py` 的 `_get_name` 只處理 `constant`，遇到 `scope_resolution` 回傳 `None`，
整個 Class 節點就被丟掉，方法也跟著變成 `parent_name = NULL` 的孤兒。

已回報上游：**https://github.com/tirth8205/code-review-graph/issues/932**
（附最小重現、AST 證據、本專案 64 檔缺 62 檔的統計）。修好之前，本專案的 Phlex
元件層在 graph 裡就是沒有類別資訊，`callers_of` / `inheritors_of` 一律查不到。

### 最重要的一個陷阱

工具回應裡有 `confidence` 欄位，它會老實說：

```
"confidence": "target not indexed: no node matching 'WatchlistManagerComponent',
               so this 0 is not evidence that none exist"
```

**「0 個呼叫端」和「查不到這個節點」是兩件事，工具分得清楚，但只寫在 `confidence`
裡。** 如果我當初用 `callers_of` 查那三個候選元件、拿到 0 就直接刪，而沒讀
`confidence`，很可能刪掉的是活的元件。

→ 用 graph 查詢時，**`confidence` 與 `status` 欄位必讀**，不能只看
`result_count`。

### 結論：怎麼用才對

| 用途 | 適不適合這個 graph |
|---|---|
| `file_summary`（某檔案有哪些節點） | ✅ 可靠 |
| `get_impact_radius`（改動的影響範圍） | ✅ 檔案層級可靠 |
| post-commit 自動 `detect_changes` 風險評分 | ✅ 已在跑，commit 後那段就是 |
| `dead_code` 找 Rails 死碼 | ❌ 194 個假陽性，不能用 |
| 用類別名反查呼叫端（`class A::B` 緊湊寫法） | ❌ 64 檔裡 62 檔沒有 Class 節點 |
| 用類別名反查呼叫端（`module A` + `class B`） | ✅ 19/19 都有節點 |

**規則修正**：不是「一律先用 graph」，而是**「先花一次呼叫確認 graph 覆不覆蓋得到
這個問題，再決定用它還是退回 Grep/Read」**。這次省掉那一次呼叫，等於連「該不該
用」都沒判斷過。

而死碼判斷這種**刪東西的決定**，無論 graph 說什麼，都要用實際執行的證據交叉驗證
（本次用的是：正式碼 `.new` 掃描 + `log/development.log` 的例外記錄 + 665 個測試
+ 瀏覽器實測）。


## 2026-08-29（五）— 對外提報必須先給草稿

### 事件

回報 `code-review-graph` 的 Ruby parser bug 時，我把使用者在選項裡挑的「2. 回報上游」
當成完整授權，查重 → 做最小重現 → 寫好內容 → **直接 `gh issue create` 送出**
（成為 [issues/932](https://github.com/tirth8205/code-review-graph/issues/932)），
草稿完全沒讓使用者看過。

事後使用者明確要求：**提報問題前先讓我看過草稿。**

### 為什麼這是錯的

那是用使用者本人的 GitHub 帳號（`idarfan`）公開發出的內容，**撤不乾淨**——issue 就算
事後 close 或編輯，原始版本已經進了 watcher 的通知信與搜尋索引。

而且 issue 裡引用了不少專案內部資訊：程式碼片段、檔案結構、「64 檔裡 62 檔缺 Class
節點」這種統計。這些要不要公開，是使用者的決定，不是我的。

**選項式提問裡的「回報上游」是「方向」的授權，不是「內容」的授權。** 我把兩者混為一談。

### 正確流程

1. 查重（`gh issue list` / `gh search issues`，掃標題關鍵字）
2. 做最小重現，取得可驗證的證據
3. **把草稿完整貼在對話裡**——標題 + 內文全文，並標明會用哪個帳號、送到哪個 repo
4. 等使用者點頭
5. `gh issue create`
6. 用 `gh issue view <n> --json ...` 驗證真的在線上，回報實際 URL 與狀態
   （不要只憑 create 指令的輸出就宣稱完成）

### 適用範圍

不只 GitHub issue：`gh pr create`、到外部 repo 留言、任何會用使用者身分對外發表、
或把專案內容送往第三方服務的動作，一律先給草稿。

對照：同一類「動作先斬後奏、使用者來不及過目」的問題還有自動提交 hook 搶先 commit
（見該則教訓），差別在 commit 可以 `git reset --soft` 收回，公開發表收不回來。

## 2026-08-29（六）— 型別化最大的風險是「把隱式強制轉型換成嚴格檢查」

### 事件

30 支 behaviors 從 `.js` 轉 `.ts`（765 個 strict error → 0）。轉換本身很機械，
但造成了一個真實回歸：**IV 分析頁的 Skew Rank 全部變成「—」、摘要計數 3/0/0
變 0/0/0、觀察清單的履約價欄整欄消失。**

根因：**Rails 把 BigDecimal 序列化成字串**。`/api/iv_analysis/watchlist` 回的是

```json
{ "skew_rank": "78.87", "strike": "100.0", "ivr_1y": 3.06 }
```

同一個 API 裡有的欄位是數字、有的是字串。原碼一律 `parseFloat()` 所以看不出
差別；我寫的收窄函式是

```ts
export function num(source: unknown, key: string): number | undefined {
  const v = source[key];
  return typeof v === "number" && !isNaN(v) ? v : undefined;   // 字串直接丟掉
}
```

字串欄位全部變 `undefined`，畫面就變成「—」。

### 規則

**把 `parseFloat` / 隱式強制轉型換成型別檢查時，必須先確認 API 實際回什麼型別，
不能假設。** 最快的確認方式是在瀏覽器直接打 API 看 `typeof`：

```js
const d = await (await fetch('/api/...')).json();
Object.entries(d.watchlist[0]).map(([k, v]) => [k, typeof v]);
```

**修法要分辨兩種原始語意，不能一律放寬：**

| 原碼寫法 | 語意 | 對應的收窄函式 |
|---|---|---|
| `parseFloat(x)` | 接受數字與數字字串 | `numeric()` |
| `typeof x === 'number'` | 字串本來就顯示「—」 | `num()`（維持嚴格）|

價差頁的 `fmt()` 屬於後者，如果為了修 ivAnalysis 就把 `num()` 一起放寬，反而
會改壞那邊本來正確的行為。

### 字面值比對：抓到一個測試與肉眼都抓不到的錯

型別化不該改動任何數值常數。寫了一支比對腳本，每批轉完就跟轉換前的 commit 比對
數值與字串字面值的多重集合。

它抓到我把 `ivEducationChart` 的 `normCDF` 常數 `0.3989422820` 打成
`0.3989422804`（1/√(2π) 的真值）。**這種錯測試抓不到、code review 也看不出來。**

差異不一定是錯（字串串接改 template literal、重複內容抽成常數都會產生差異），
腳本只負責把差異攤開；需要解釋的再逐一程式化驗證是否逐字相同。

### 改副檔名會動到 Rails 端

`entrypoints/application.js` → `.ts` 之後 `vite_javascript_tag 'application'`
**解析失敗**（`ViteRuby.instance.manifest.path_for` 直接拋錯），整站白畫面。
要改成 `vite_typescript_tag 'application.ts'`。

改 entrypoint 副檔名前先跑：

```ruby
RAILS_ENV=production bin/rails runner 'puts ViteRuby.instance.manifest.path_for("x.ts", type: :typescript)'
```

### 幾個 TS 本身的坑

- **`instanceof` narrowing 在巢狀 function declaration 裡不保證留存**。與其到處
  寫 `!` 非空斷言，不如在 guard 之後宣告一個明確型別的 const
  （`const btn: HTMLButtonElement = found;`），整批轉換因此零個 `!`。
- **在 `forEach` callback 裡賦值，TS 看不到那次賦值**，會把變數窄化成 `never`。
  改用 `for...of`。
- **`no-irregular-whitespace` 不管單引號字串，但管 template literal**。原碼裡
  刻意的全形空格分隔符改成 template literal 就會被擋，維持字串串接即可。

### 自己造出來的死碼

`shared/dom.ts` 一開始寫了 `byId()` 與 `isWithin()`，轉完 25 個模組後零呼叫端
——正是這個 codebase 前一輪剛清掉的同一種東西。刪掉之後順帶消除了整批唯一的
`as`（`byId` 的 `as T | null`）。**寫工具函式時先確認真的有人要用。**

## 2026-08-29（七）— 「裝不了套件」通常是兩個獨立衝突疊在一起

### 事件

整個 session 裡我三次說「`npm install` 卡在 vite 的 peer dependency 衝突，
裝不了新套件」，並據此放棄用 Zod、放棄裝 DOM 測試環境。實際動手升級才發現：

1. `@vitejs/plugin-react@6.0.1` 要 `vite@^8`，專案釘 `vite@^6.4.1`
2. `eslint-plugin-react-hooks@7.0.1` peer 只到 `eslint@^9`，專案已裝 `eslint@10.2.0`

**第二個是修完第一個才浮出來的。** 只看第一次的錯誤訊息會以為只有一個問題。

而且我還說錯了一件事：「這專案沒有前端測試框架、`npx vitest` 跑不了」——
**`vitest@4.1.1` 早就裝好了**，缺的只是 DOM 環境。我沒查就下了結論。

### 規則

**「裝不了」不是終點，是待查的症狀。** 遇到 ERESOLVE 要做三件事：

1. **看完整錯誤**，不要只看 `tail`——npm 會把真正的衝突印在中段
2. **查每個消費端的 peer 範圍**，確認升級目標是否真的可行：
   ```bash
   python3 -c "import json; [print(p, json.load(open(f'node_modules/{p}/package.json')).get('peerDependencies',{}).get('vite')) for p in [...]]"
   ```
   註：這些套件多半是 ESM-only，`require()` 會失敗，直接讀 `package.json` 比較可靠
3. **確認實際安裝了什麼**，`package.json` 的宣告與 `node_modules` 可能不一致
   （本例：eslint 宣告與安裝都是 10，但 plugin 的 peer 只到 9——先前用 `--force` 裝的）

### 升級前的檢查清單

升 vite 這種核心建置工具前，先列出所有消費端的 peer 範圍再動手：

```
vite-plugin-ruby      >=5.0.0                      ✓
@storybook/react-vite ^5||^6||^7||^8               ✓
vitest@4.1.1          ^6||^7||^8                   ✓
@vitejs/plugin-react  ^8（就是它逼著要升）          ✓
```

升完之後**至少要驗這三件**：Rails 端 `bundle exec vite build` 能跑、manifest
的 entrypoint 與 chunk 數量不變、chunk hash 全換所以要重啟並重驗頁面。

本例 vite 6 → 8 的意外收穫：production build 從約 10 秒降到 1.80 秒。

### 殘留的不相容要講清楚，不要當作沒事

升完仍有一個 peer 不符：`@joshwooding/vite-plugin-react-docgen-typescript`
（Storybook 的相依）只支援到 vite 7。**它只影響 Storybook，不影響 Rails 建置**，
所以沒有為它再動 Storybook——但必須寫進 README 與交接說明，因為
`npx chromatic` 是這個專案的既有流程。

### 沒有測試資料時怎麼驗一個模組

`portfolioHoldings` 因為 `/portfolio` 是空的而長期沒驗過。解法不是「建假資料
進資料庫」，而是**照元件真實標記建合成 DOM、載入 chunk 呼叫 `init()`、
攔截 fetch 回真實形狀的 payload**，再拿渲染結果跟手算對照。

```js
window.fetch = (url, opts) => url.includes('/portfolio/quotes')
  ? Promise.resolve(new Response(JSON.stringify({ AAPL: { c: 319.7, d: 5.12, dp: 1.6276 } })))
  : realFetch(url, opts);
const mod = await import('/vite/assets/portfolioHoldings-<hash>.js');
mod.init();
```

前提是**payload 形狀要有依據**——我先用 `rails runner` 確認 Finnhub 回的是
`Float`，才敢用 number 型別餵進去。憑印象捏形狀等於沒驗。
