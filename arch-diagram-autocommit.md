# arch-diagram-autocommit.md — 架構圖隨 push 一起推上 GitHub

## 問題回報（給使用者）

- **日期時間**：2026-11-11 14:38（Asia/Taipei）
- **現況**：FairPrice 的 pre-push hook（使用者要求的功能）每次 push 前重新產生 `docs/` 架構圖，但不 commit。
- **症狀**：push 出去的是舊架構圖；push 後工作區每次多出 3 個未 commit 的 docs/ 修改，干擾後續驗收。
- **主訴**：要讓新產生的架構圖跟著推上去。

## 找到的問題

git 在 pre-push 執行時，要推的 commit 已經決定好；hook 內新建的 commit **不會**被這次 push 帶上。所以「pre-push 產生後直接 commit」無法讓圖跟著同一次 push 出去。

## 修改策略（使用者定案：方案 A）

每次 commit 前（pre-commit）產生架構圖，有變動就 `git add` 進同一個 commit；pre-push 移除產生步驟。保證 push 到 GitHub 的永遠是最新架構圖，push 後工作區乾淨。

## 建議修改順序

S0 定位與實測 → S1 依實測選方案實作＋測試 → S2 實際 push 驗收。

## 怎麼測試

S1 在暫存 git repo（含假遠端 bare repo）跑情境；S2 實際 push 一次，比對 GitHub 上的圖與本機一致、工作區乾淨。

## 怎麼回報

每階段 patch 狀態表；最終附：選用方案與實測秒數、hook 路徑與 diff、push 後 `git status`、遠端圖檔 blob hash 與本機比對。

---
（以下給 Claude Code）

## 執行狀態表

| 階段 | 內容 | 狀態 | 驗證證據 | 審查 |
|---|---|---|---|---|
| S0 | 定位 pre-push hook、實測產生時間 | 未開始 | | |
| S1 | 實作方案 A＋測試 | 未開始 | | |
| S2 | 實際 push 驗收 | 未開始 | | |

規則：驗證未過禁止進入下一階段；每階段過驗證立即 patch 本表；接續 session 只讀本表＋進行中階段。每階段完成交審查官，審查欄填「異端審查官表示:」結論後才算完成。

## 全域限制

- 架構圖的產生邏輯（產出內容）不改，只改觸發時機與 commit 行為。
- 不得 `--no-verify`、不得 hook 內自行 `git push`（避免遞迴）。
- 產生失敗時：方案 A 中止 commit、方案 B 中止 push，皆印出錯誤；不得靜默放行。
- 自動 commit 只能包含架構圖檔案，不得 `git add -A`。

## S0 定位與實測

動作：
1. 找出 pre-push hook 的實際位置（`.git/hooks/pre-push`、`core.hooksPath`、lefthook／overcommit 等設定），記錄絕對路徑與產生架構圖的指令。
2. 列出它產生／修改的檔案清單（目前已知 docs/ 下 3 個，逐一列名）。
3. 在工作區乾淨狀態下連跑 3 次產生指令，記錄每次秒數（`/usr/bin/time -f %e`），取最大值。
4. 確認產生結果是否具決定性：連跑兩次、無程式變動時，圖檔內容是否相同（`sha256sum` 比對）。若不相同（例：內含時間戳），記錄差異處。

驗證：路徑 `test -f`；3 次秒數與 sha256 結果寫入證據欄。

實測秒數只供記錄（每次 commit 會多等這麼久），不影響方案。若第 4 點不具決定性 → **停止回報**（否則每次 commit 都會夾帶無意義的圖檔變動），由使用者決定是否先修正產生邏輯。

## S1 實作

### 方案 A（pre-commit）
- 擴充既有 pre-commit hook（如 `pre-commit-rubocop.sh` 所在的鏈），既有檢查順序在前，產生架構圖在後：執行產生指令 → 若 S0 清單內檔案有變動 → `git add <清單內檔案>`。
- 從 pre-push 移除產生步驟。
- 產生指令必須以**暫存區內容**為準不可行時（產生器讀工作區），在證據欄註明：工作區有未暫存的程式改動時，圖可能反映未 commit 的程式。

### 測試腳本
在 `mktemp -d` 建工作 repo＋bare 遠端，以替身產生指令（寫入可控內容）跑：

| 案例 | 預期 |
|---|---|
| T1 程式改動使圖需更新 | commit 內含更新後的圖檔；push 後遠端含新圖 |
| T2 圖無需更新 | commit 不含圖檔；push 一次成功 |
| T3 產生指令失敗 | commit 中止，印出錯誤 |
| T4 工作區另有無關未 commit 檔 | 自動 commit 不含該檔 |

驗證：4 案全過；T1 必須在**舊 hook** 下失敗（遠端圖為舊版），送審附新舊兩次輸出。

## S2 實際 push 驗收

在 `/home/idarfan/fairprice`：
1. 先處理目前 docs/ 3 個已追蹤、有未 commit 修改的檔：照既有做法檢查內容後單獨 commit。
2. 做一個會讓圖需要更新的小 commit，再正常 push（使用者手動執行）。
3. 驗證：
   - push 後 `git status --porcelain` 無 docs/ 架構圖檔。
   - 每個架構圖檔：`git rev-parse HEAD:<檔>` 與 `git rev-parse origin/<branch>:<檔>` 相同。
   - 再 push 一次（無新變動）不產生新 commit。

不需重啟 server。
