# LEAPS 頁面改為 Stale-While-Revalidate 模式

## 問題

目前 `fresh` scope 限制 5 分鐘內，超過 5 分鐘的資料一律不顯示，使用者每次重開頁面都看到空白、必須重新等 3-5 分鐘抓取。對 LEAPS 候選篩選這個使用情境（天期 364 天以上的長線決策）來說，資料差幾小時對判斷幾乎沒有影響，但每次重開頁面都要重等這個成本是真實且不必要的。

## 目標行為（Stale-While-Revalidate）

1. 使用者進入頁面（或按查詢）
2. **如果 DB 有任何快取資料（不管幾小時前的）→ 立刻顯示**，讓使用者馬上看到上次的結果
3. **同時在背景觸發重新抓取**（不阻擋畫面顯示）
4. 抓取完成後，畫面自動更新成新資料（沿用現有的 polling/Turbo Stream 機制）
5. 如果完全沒有任何快取資料 → 維持現有行為（顯示「請點查詢」）

## 需要修改的地方

**第一步：先讀清楚這幾個檔案的現有邏輯，不要憑印象改**

- `app/controllers/leaps_recommendations_controller.rb`：`index` 跟 `analyze` action 的完整邏輯
- `app/models/leaps_option_chain_snapshot.rb`：`fresh` scope 的定義
- 現有的 polling/Turbo Stream 機制在哪裡、怎麼運作

讀完之後回報你看到的結構，再動手改，不要邊猜邊改。

**第二步：修改 `analyze` action 的判斷邏輯**

目前 `analyze` 的邏輯大概是：
```
if fresh_data_exists?
  return { status: "ready" }  # 不重新抓
else
  dispatch ScrapeLeapsJob  # 重新抓
end
```

改成：
```
if any_data_exists?  # 有任何快取資料（不限5分鐘）
  dispatch ScrapeLeapsJob  # 背景重新抓（不阻擋）
  return { status: "revalidating", has_stale_data: true }  # 告訴前端「有舊資料可以先顯示」
else
  dispatch ScrapeLeapsJob
  return { status: "fetching" }  # 沒有任何資料，等抓取完成
end
```

**第三步：修改 `index` action**

目前只有在 `fresh_data_exists?` 時才顯示表格。改成：
- 有任何快取資料（`any_data_exists?`）→ 顯示表格（加上一個小提示「資料可能不是最新，背景更新中...」，更新完成後提示消失）
- 完全沒有資料 → 顯示「請點查詢」

**第四步：修改前端 polling 邏輯**

`status: "revalidating"` 是新狀態，前端 polling 收到這個：
- 立刻導回 `index`（顯示舊資料）
- 繼續 polling 等待背景抓取完成
- 抓取完成收到 `status: "ready"` → refresh 頁面顯示新資料

## 新增 model scope

```ruby
# 現有
scope :fresh, -> { where(scraped_at: 5.minutes.ago..) }

# 新增
scope :any_cached, -> { where(symbol: ...) }  # 只要有資料就算，不限時間
```

（實際寫法對照現有 scope 的慣例，不要照抄）

## 驗收

1. DB 有超過 5 分鐘的舊資料時，進入頁面或按查詢，**表格立刻顯示舊資料**，不會先空白
2. 同時背景有在抓取（可從 Rails log 或 job queue 確認）
3. 抓取完成後，畫面自動更新成新資料
4. DB 完全沒有任何資料時，行為跟之前一樣（顯示「請點查詢」）
5. 用 Playwright 截圖驗證第1點：截圖要顯示有舊資料的表格，不是空白頁面
6. 改完所有現有測試仍然通過，並補上新的測試覆蓋「有舊資料時立刻顯示」這個情境

commit 前把截圖跟測試結果一起回報。
