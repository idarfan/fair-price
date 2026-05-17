# PATCH: 在 FairPrice 側邊欄加入 IV Skew 追蹤

> 這是獨立的補丁，在完成 BUILD_IV_SKEW_COMPLETE.md 之後執行。
> 只需修改導覽列元件，不涉及其他檔案。

---

## Step 1：找到導覽列元件

```bash
# 搜尋包含「IV 分析」字串的元件檔案
grep -r "IV 分析" app/views --include="*.rb" -l
grep -r "IV 分析" app/components --include="*.rb" -l
```

確認找到正確的 Phlex 元件檔案後進行下一步。

---

## Step 2：插入新項目

在找到的導覽列元件中，找到「IV 分析」那個工具項目的程式碼區塊，
在它的**正下方**、「Watchlist」項目的**正上方**插入以下內容，
風格必須與相鄰項目完全一致：

```
名稱：IV Skew 追蹤
副標題：Put/Call Skew · 底部訊號偵測
路由：/iv_watchlists
圖示：與「IV 分析」風格一致（emoji 或 icon）
```

插入前請先閱讀相鄰項目的完整結構，複製相同的 HTML 標籤、
class 名稱、data 屬性，只替換名稱、副標題、路由、圖示。

---

## Step 3：驗證

```bash
rails server
```

開啟瀏覽器，點擊「切換工具」下拉選單，確認：

1.「IV Skew 追蹤」出現在「IV 分析」正下方
2. 點擊後正確導向 `/iv_watchlists`
3. 外觀與其他項目一致
