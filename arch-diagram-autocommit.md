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
| S0 | 定位 pre-push hook、實測產生時間 | 完成 | pre-push：`/home/idarfan/fairprice/.git/hooks/pre-push`（未版控；無 `core.hooksPath`、無 lefthook／overcommit／husky／pre-commit-config），第 38–39 行 `python3 ~/.claude/scripts/gen_arch_spec.py <repo>`、`python3 ~/.claude/scripts/gen_architecture.py <repo>`，graph.db 不在就跳過，永遠 exit 0。產生檔案：`docs/architecture_spec.yml`、`docs/fairprice-architecture.svg`、`docs/fairprice-architecture.html`（`.excalidraw` 不在產出內）。乾淨工作區連跑 3 次：0.19／0.17／0.34 秒，最大 0.34 秒（只記錄）。決定性：3 次 sha256 皆與 HEAD 相同（spec 53f555d7…、svg 3d7a4eae…、html c7a01760…），跑完工作區仍乾淨。輸入來源：`gen_arch_spec.py` 讀 `.code-review-graph/graph.db`（sqlite；「自動化腳本」層的 scraper 名稱來自 `get_python_items` :167-188 查 `nodes WHERE language='python'`）、工作區設定檔，以及 :203-209 glob `<repo>/scripts/*.py`、`<repo>/backend/scripts/*.py`（只用來偵測外部依賴；S0 r1 審查更正，原誤寫為 `lib/barchart_scrapers/*.py`）；`gen_architecture.py` glob 工作區 app/ 檔案並讀 spec → **讀工作區與 graph.db，不讀暫存區**。graph.db 由 Claude PostToolUse（Edit\|Write\|Bash）`code-review-graph update --skip-flows` 更新，終端機直接改檔不會更新（實測 update 約 2.2–2.4 秒；patch2 追加：2026-11-11 連跑 3 次 `code-review-graph update --skip-flows` 為 1.90／1.87／1.83 秒，最大 1.90 秒）。既有 pre-commit：git `.git/hooks/pre-commit`（code-review-graph 安裝，`detect-changes --brief \|\| true`）；`pre-commit-rubocop.sh` 是 `~/.claude/settings.json` 的 Claude PreToolUse（Bash，指令含 `git commit` 才跑），終端機 commit 不經過。 | 異端審查官表示: VERDICT: PASS（verdict-arch-diagram-autocommit-S0-r1.md） |
| S1 | 實作方案 A＋測試 | 完成 | 新增 `bin/arch-diagram-precommit`（版控、可執行）：`code-review-graph update --skip-flows` → 兩支產生器 → docs/ 三檔有變動才 `git add -- <三檔>`；任一步失敗印錯並 exit 1。`.git/hooks/pre-commit` 在 detect-changes 之後加 `bin/arch-diagram-precommit \|\| exit 1`；`.git/hooks/pre-push` 移除產生步驟（只讀 stdin、exit 0；原版備份於 evidence）。README「重新 clone 後要補的 git hook」。測試 `script/arch_diagram_precommit_test.sh`（替身產生器＋假 code-review-graph update，bare 遠端）：舊 hook 1 過 6 敗（T1 遠端無新圖），新 hook T1–T6（T6 含不存在／不可執行）7/7。實環境直接跑腳本：真 update＋真產生器，「架構圖沒有變動」exit 0、未 add 任何檔。**產生器讀工作區與 graph.db、不讀暫存區**：工作區有未暫存的程式改動時，圖可能反映未 commit 的程式（patch1 要求註明）。shellcheck 0。審查後依使用者裁示追加（未另出 patch）：(1) README 已知限制——先 `git add` 再 commit，`git commit <檔案>` 會暫時留下 `MM`、下次 commit 自動恢復（實測 commit_variants.txt），勿用 `--no-verify`；(2) 暫存 clone 實測沒有 graph.db 時 `update` 會建出 0 節點空 graph.db 並 exit 0，產生器畫出只剩 1 層的圖被併進 commit → 腳本在 update 前檢查 graph.db 存在且 `code-review-graph status` Nodes > 0，否則印「請先執行 code-review-graph build…」並中止（使用者原指定訊息為 install；實查 install 不建圖譜，改寫 build，待使用者確認）；新增 T7（無／空 graph.db），新 hook 9/9，舊 hook 1 過 8 敗；失敗訊息改為「請勿用 --no-verify 跳過」。 | 異端審查官表示: VERDICT: PASS（verdict-arch-diagram-autocommit-S1-r1.md；審查後追加項目於 S2 送審一併檢查） |
| S2 | 實際 push 驗收 | 完成 | 步驟 1：docs/ 三檔已於 b68f697 單獨 commit。步驟 2（使用者選 (a)）：乾淨工作區直接產生一次，blob 與 HEAD 相同（spec 7ff9921、svg b5be30c、html 5a0e9cb）；暫存區刻意放入舊版（b68f697^：ec9862a／f1c8548／387a254）後 `git commit --allow-empty -m "docs: 驗收架構圖自動更新（S2）"` → hook 印「架構圖已更新，併入這次 commit」，c1b6081 內三檔 blob＝乾淨產生結果、≠ 舊版，commit 後工作區乾淨。使用者 push（含 346688f…c1b6081 共 6 筆）後：`git status --porcelain` 空；三檔 mtime 15:34:53（S2 commit 時 pre-commit 產生），pre-push 未再產生；三檔 `HEAD:` 與 `origin/feat/leaps-iv-environment:` blob 相同；ls-remote＝c1b6081。使用者再 push 一次：HEAD／origin／ls-remote 仍為 c1b6081，未產生新 commit，工作區乾淨。GitHub API（`gh api repos/idarfan/fair-price/contents/<檔>?ref=feat/leaps-iv-environment`）三檔 sha＝7ff9921／b5be30c／5a0e9cb，與本機 HEAD 相同；GitHub 分支 head＝c1b6081（S2 r1 質詢 2）。 | 異端審查官表示: VERDICT: PASS（verdict-arch-diagram-autocommit-S2-r1.md） |

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
- 掛在 git 的 `/home/idarfan/fairprice/.git/hooks/pre-commit`，排在既有 `code-review-graph detect-changes` 之後（任何地方 commit 都會觸發；Claude Code commit 時其 rubocop hook 仍先跑完）。不修改 `~/.claude/hooks/pre-commit-rubocop.sh`。
- 流程：`code-review-graph update --skip-flows`（先更新 graph.db，使終端機／IDE 直接改的程式也反映在圖上）→ 執行產生指令 → 若 S0 清單內檔案有變動 → `git add <清單內檔案>`。
- 上述流程寫在 `/home/idarfan/fairprice/bin/arch-diagram-precommit`（納入版控、可執行）；`.git/hooks/pre-commit` 只加一行呼叫它並傳回其結束碼。
- README 補一段「重新 clone 後，在 `.git/hooks/pre-commit` 加入：`bin/arch-diagram-precommit || exit 1`」。
- `update` 或產生任一步失敗 → commit 中止並印出錯誤。
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
| T5 不經 Claude Code、直接修改程式檔後 commit | graph.db 被更新，commit 內的圖反映該修改 |
| T6 `bin/arch-diagram-precommit` 不存在或不可執行 | commit 中止並印出錯誤，不靜默放行 |

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
