# LEAPS 頁面版面修正（Options Flow + LEAPS 候選排行）

## 目前問題

1. `Call $X.XM Put $X.XM` 匯總金額浮在右上角，跟「Options Flow — 情緒參考，非排序依據」標題脫節
2. Options Flow 表格所有欄位標頭跟對應的資料沒有置中對齊
3. **LEAPS 候選排行表也歪斜**：標頭跟資料列對齊方式不一致——例如「履約價」「Delta」「OI」「Time Value%」「IV」的資料都往左偏離標頭，「被指派機率」「Vega」的「—」沒有對在標頭正下方。看起來是標頭（`<th>`）跟資料（`<td>`）各自用了不同的 text-align 或 padding

## 目標版面

- 標題跟匯總金額在同一行：左側標題、右側 Call/Put 金額
- Options Flow 表格**所有欄位**（類型、履約價、到期日、DTE、Delta、Code、Size、Side、Premium、方向）：標頭跟資料都用 `text-align:center`，統一置中
- LEAPS 候選排行表**所有欄位**（到期日、DTE、履約價、Delta、OI、Volume、流動性判斷、Bid、Ask、Mid、Spread%、Time Value%、IV、Vega、被指派機率）：同樣統一 `text-align:center`，標頭跟資料每一欄都要垂直對齊在同一條中線上，兩張表用同一套對齊規則

## 第一步：先讀清楚現有程式碼，不要憑印象改

開啟 `app/components/leaps_recommendations/page_component.rb`，找到 Options Flow 跟 LEAPS 候選排行兩個區塊的渲染位置，把以下五段程式碼完整貼出來再動手：

1. Options Flow 標題那一段（包含 Call/Put 匯總金額的位置）
2. Options Flow 表格 `<th>` 標頭那一段
3. Options Flow 表格 `<td>` 資料列那一段
4. LEAPS 候選排行表 `<th>` 標頭那一段
5. LEAPS 候選排行表 `<td>` 資料列那一段

特別注意第 4、5 段：把每一欄 `<th>` 跟對應 `<td>` 目前實際使用的對齊 class / inline style 列成對照表，指出哪幾欄標頭跟資料的對齊不一致（這就是歪斜的來源），確認找對位置後再進行第二步。

## 第二步：修改標題區

把 Options Flow 標題區改成 flex 布局（用查到的實際變數名稱替換佔位符）：

```ruby
div(class: "flex justify-between items-center mb-1") do
  div do
    h2(class: "text-base font-semibold") { plain "Options Flow — 情緒參考，非排序依據" }
    p(class: "text-xs text-gray-500 mt-0.5") do
      plain "#{實際日期變數} · 前 20 大成交（依 Premium 降序）"
    end
  end
  div(class: "text-sm font-medium whitespace-nowrap pl-4") do
    span(class: "text-green-600") { plain "Call #{實際Call金額格式化}" }
    span(class: "text-gray-400 mx-1") { plain "·" }
    span(class: "text-red-500") { plain "Put #{實際Put金額格式化}" }
  end
end
```

## 第三步：修改表格對齊（兩張表都要改）

**Options Flow 表格**與 **LEAPS 候選排行表**：所有 `<th>` 跟 `<td>` 一律改成 `text-center`（Tailwind）或 `text-align: center`（inline style）。同一欄的 `<th>` 跟 `<td>` 必須用完全相同的對齊方式，不允許標頭一種、資料另一種。

不改動的部分：

- Options Flow：類型欄的 Call/Put 文字顏色維持（Call 綠色、Put 紅色），Delta 負值維持顏色，Code 維持顏色
- LEAPS 候選排行：流動性判斷欄的 badge（充足/普通）樣式與顏色維持，空值「—」的呈現方式維持

只改對齊，不改顏色、不改內容、不改欄位順序。

## 驗收（不做完這步不算修好）

1. 執行 `mcp__playwright-chrome__browser_navigate` 導航到 `http://localhost:3003/leaps?symbol=NOK`
2. 等資料載入完成
3. 執行 `mcp__playwright-chrome__browser_take_screenshot` 截圖，**必須同時涵蓋 LEAPS 候選排行表與 Options Flow 兩個區塊**（一張截不下就分兩張）
4. 截圖必須顯示：
   - Options Flow 標題左、Call/Put 金額右，同一行
   - Options Flow 所有欄位標頭跟對應資料置中對齊，沒有左右偏移
   - LEAPS 候選排行表所有欄位標頭跟對應資料置中對齊，特別檢查先前歪斜的欄：履約價、Delta、OI、Time Value%、IV、Vega、被指派機率——資料必須落在標頭正下方
5. 把截圖貼出來，不接受只有文字說「修好了」

截圖確認正確後才 commit。
