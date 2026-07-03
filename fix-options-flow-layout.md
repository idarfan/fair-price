# Options Flow 版面修正指示

## 問題

`Options Flow — 情緒參考，非排序依據` 標題跟右邊的 `Call $X.XM Put $X.XM` 匯總金額目前是分離的——匯總金額浮在右上角，跟標題沒有在同一個 flex 容器裡，視覺上看起來脫節。這個問題已經被提出三輪，每次都沒有修到正確的位置。

## 要修的檔案

`app/components/leaps_recommendations/page_component.rb`

找到 Options Flow 區塊的標題部分，把它改成 flex 布局讓標題跟匯總金額在同一行。

## 修法

**第一步：先查清楚實際用的變數名稱和 helper，不要照抄下面的範例**

在 `app/components/leaps_recommendations/page_component.rb` 裡搜尋 Options Flow 區塊的標題渲染位置，找出：
- 日期那個變數實際叫什麼（不一定是 `@flow_date`）
- Call/Put 總金額的變數實際叫什麼（不一定是 `@call_premium_total`、`@put_premium_total`）
- 金額格式化的 helper 實際叫什麼（不一定是 `fmt_money`）

查清楚之後，把外層容器改成以下結構（用你查到的實際變數名稱替換掉佔位符）：

```ruby
div(class: "flex justify-between items-start mb-1") do
  div do
    h2(class: "text-base font-semibold") { plain "Options Flow — 情緒參考，非排序依據" }
    p(class: "text-xs text-gray-500 mt-0.5") { plain "#{@flow_date} · 前 20 大成交（依 Premium 降序）" }
  end
  div(class: "text-sm font-medium shrink-0 pt-0.5") do
    span(class: "text-green-600") { plain "Call #{fmt_money(@call_premium_total)}" }
    plain "  "
    span(class: "text-red-500") { plain "Put #{fmt_money(@put_premium_total)}" }
  end
end
```

## 驗收

改完之後：

1. 用 `mcp__playwright-chrome__browser_navigate` 導航到 `http://localhost:3003/leaps?symbol=NOK`
2. 用 `mcp__playwright-chrome__browser_take_screenshot` 截圖
3. 截圖要顯示：「Options Flow — 情緒參考，非排序依據」跟「Call $X.XM Put $X.XM」在同一行，左邊標題、右邊金額，不是金額浮在右上角跟標題完全脫節的樣子
4. 把截圖貼出來，不要只回報「修好了」

確認截圖正確後才 commit，不要先 commit 再說。
