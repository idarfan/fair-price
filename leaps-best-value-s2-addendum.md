# S2 補充：兩個 request spec 邊界案例

BASE：`13faac3`。S3 開工前完成，單獨 commit。

## 範圍

只新增測試案例；若案例揭露 controller 行為錯誤，才可改 controller。不改畫面、不改規格、不動回歸基準。

## 案例 1：資料不夠新、不產生推薦的路徑

- 動作：在 `spec/requests/leaps_recommendations_spec.rb` 建立會讓 controller 走「不產生推薦」分支的資料狀態（S0／S2 已知的那條分支條件，例如快照過舊或無快照），打 `GET /leaps?symbol=NVDA`。
- 斷言：
  1. 回 200。
  2. `LeapsBestValueService` 未被呼叫（`expect(...).not_to receive`）。
  3. `PageComponent` 收到的 `best_value` 為 `nil`。
  4. body 不含例外訊息（不含 `Error`、`undefined method`）。

## 案例 2：帶履約價（參數 `user_strike`）

用 S2 的 11 筆驗收基準資料。`fresh_for?` 以 `StrikeChainSnapshot.last_query_strike` 判定新鮮度，故分兩案：

- 2a：`last_query_strike` 設為 180，打 `GET /leaps?symbol=NVDA&user_strike=180`。
  預期：OI 推薦有產生；`LeapsBestValueService` 被呼叫一次，近天期主推 `$130 / 2028-01-21`。
- 2b：`last_query_strike` 不是 180（上次未帶履約價），打 `GET /leaps?symbol=NVDA&user_strike=180`。
  預期：OI 推薦不產生；服務未被呼叫、`best_value` 為 `nil`；回 200、body 無例外訊息。
- 2c：打 `GET /leaps?symbol=NVDA&strike=180`（錯誤參數名）。斷言結果與不帶履約價相同（`strike` 被忽略），防止日後誤以為 `strike` 有效。

兩案皆先跑一次確認既有 OI 推薦的實際行為；實際行為與上述預期不同時，以實際行為寫斷言並在回報中註明差異。不得為了讓測試通過而改既有 OI 推薦邏輯或 `fresh_for?`。

## 驗證

1. 兩案先寫、先跑：記錄改 controller 前的結果（通過或失敗皆記）。
2. `bundle exec rspec spec/requests/leaps_recommendations_spec.rb` 0 failures。
3. 完整 rspec：
   ```
   bundle exec rspec 2>/dev/null --format progress --format failures --out tmp/rspec-failures.txt
   ```
   0 failures；記下輸出的 `Randomized with seed` 數字；若有失敗，附 `tmp/rspec-failures.txt` 案例名稱。
4. 整頁 HTML 回歸比對全過、基準檔無變更（`git diff --stat spec/` 不含基準檔）。

## 回報

狀態表 S2 證據欄 patch 追加一句：案例 1 的分支條件、案例 2a／2b／2c 的實際行為、seed 數字、新 commit hash。送審查官確認後才開始 S3。
