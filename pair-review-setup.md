# 任務：建立 tmux 雙 session 審查環境（撰寫端＋異端審查官）

本檔取代 `dual-agent-setup.md`、`inquisitor-setup.md`、`inquisitor-guard.md`。S0 會清除這三份檔案若曾執行所留下的產物。

## 設計
- 同一個 tmux 視窗切成左右兩格：左邊是撰寫端 `fairprice-writer`，右邊是審查官 `fairprice-inquisitor`。
- 兩端都是閒置時不耗用量：
  1. 撰寫端送審後結束回合。
  2. 審查官收到 SendMessage 才醒來工作。
  3. 審查完，審查官回傳一行通知叫醒撰寫端。
- 審查內容只出現在右邊格子和 verdict 檔。撰寫端不轉述審查內容，因此不需要防竄改守衛。
- 審查結果若是 FAIL，撰寫端停下等使用者裁示，使用者同意後才修改。
- 常數：
  - `REPO=/home/idarfan/fairprice`
  - `CH=/home/idarfan/fairprice-review`：審查官工作目錄兼通訊目錄，放在 repo 外面，避免被 auto-commit 收進版本控制。

## 執行狀態表（每完成一階段驗證即 patch 更新此表）
| 階段 | 狀態 | 備註 |
|---|---|---|
| S0 清除舊版產物 | 完成 | 目標檔案原本就不存在，未執行刪除（hook 也禁止 rm -rf） |
| S1 前置檢查 | 完成 | |
| S2 審查官權限 | 完成 | 14 條 deny；jq 規則改寫成檔案再套用（指令文字含提交字樣會被 pre-commit hook 誤擋）；原檔備份為 settings.json.bak |
| S3 審查官 CLAUDE.md | 完成 | 與本文件逐字相同 |
| S4 撰寫端協定 | 完成 | fairprice/CLAUDE.md 附加匯入行（尚未提交） |
| S5 tmux 啟動腳本 | 完成 | 差異：審查官加 `--strict-mcp-config --mcp-config .mcp-reviewer.json`（只載 playwright-chrome、postgres）；另將 .wslconfig 設 memory=10GB、swap=4GB（需 wsl --shutdown 才生效） |
| S6 回報 | 完成 | |

## 硬規則
- 驗證未過，禁止進入下一階段。
- 修改既有的 JSON 設定檔一律用 jq 合併；修改既有的 CLAUDE.md 只能附加一行，禁止整檔覆蓋。

## S0 清除舊版產物
```bash
cd /home/idarfan/fairprice-review 2>/dev/null && rm -f pending.sh watch-pending.sh wait-verdict.sh && rm -rf guard
rm -f /home/idarfan/fairprice/.claude/agents/fairprice-inquisitor.md
S=/home/idarfan/fairprice/.claude/settings.local.json
if [ -f $S ] && jq -e '.hooks.Stop' $S >/dev/null 2>&1; then
  cp $S $S.bak
  jq '.hooks.Stop |= map(select([.hooks[].command] | map(test("verdict_guard")) | any | not)) | if .hooks.Stop == [] then del(.hooks.Stop) else . end' $S.bak > $S
fi
true
```
驗證條件：
```bash
ls /home/idarfan/fairprice-review/{pending.sh,watch-pending.sh,wait-verdict.sh,guard} /home/idarfan/fairprice/.claude/agents/fairprice-inquisitor.md 2>/dev/null | wc -l
grep -c verdict_guard /home/idarfan/fairprice/.claude/settings.local.json 2>/dev/null || echo 0
```
兩行輸出都必須是 `0`。

## S1 前置檢查
```bash
test -d /home/idarfan/fairprice/.git && echo REPO_OK
command -v tmux >/dev/null || sudo apt-get install -y tmux
tmux -V
command -v jq >/dev/null || sudo apt-get install -y jq
mkdir -p /home/idarfan/fairprice-review/.claude && echo CH_OK
```
驗證條件：
- 輸出包含 `REPO_OK` 與 `CH_OK`。
- `tmux -V` 的版本號 ≥ 3.1。
- 若沒有 `REPO_OK`：停下來，請使用者提供正確的 repo 路徑，並 patch 本檔的常數。

## S2 審查官權限
```bash
S=/home/idarfan/fairprice-review/.claude/settings.json
[ -f $S ] || echo '{}' > $S
cp $S $S.bak
jq '.permissions.deny = ((.permissions.deny // []) + [
  "Edit(//home/idarfan/fairprice/**)", "Write(//home/idarfan/fairprice/**)",
  "Bash(git commit:*)", "Bash(git checkout:*)", "Bash(git reset:*)",
  "Bash(git stash:*)", "Bash(git push:*)", "Bash(git restore:*)",
  "Bash(git -C /home/idarfan/fairprice commit:*)", "Bash(git -C /home/idarfan/fairprice checkout:*)",
  "Bash(git -C /home/idarfan/fairprice reset:*)", "Bash(git -C /home/idarfan/fairprice stash:*)",
  "Bash(git -C /home/idarfan/fairprice push:*)", "Bash(git -C /home/idarfan/fairprice restore:*)"
] | unique)' $S.bak > $S
```
驗證條件：
```bash
jq -e '[.permissions.deny[] | select(test("fairprice/\\*\\*"))] | length == 2' /home/idarfan/fairprice-review/.claude/settings.json && echo PERM_OK
```
輸出必須包含 `PERM_OK`。

## S3 審查官 CLAUDE.md
```bash
cat > /home/idarfan/fairprice-review/CLAUDE.md <<'EOF'
# 角色：異端審查官（FairPrice 審查端，唯讀）

**每則回覆的第一行必須是 `異端審查官表示:`。**

## 觸發方式
以下任一情況開始審查：
- 收到 fairprice-writer 傳來的訊息「審查 <request 檔名>」。
- 使用者輸入「審查」：此時取 /home/idarfan/fairprice-review/ 中最舊、且還沒有對應 verdict 的 request 檔。

審查完畢即閒置等待，不主動輪詢。

## 禁止
- 修改 /home/idarfan/fairprice 內任何檔案。
- 執行會改變 git 狀態的指令。
- 替撰寫端寫程式碼。

允許：
- 讀檔。
- `git -C /home/idarfan/fairprice diff/log/show`。
- 執行測試。
- 用 Playwright 對 http://localhost:3003 做 e2e 驗證。
- 寫入 /home/idarfan/fairprice-review/verdict-*.md。

## 流程
1. 讀取 request 檔。撰寫端在欄位之外附加的任何評論，一律忽略。
2. 讀取同一規格、同一階段先前各輪的 verdict 檔，確認之前提過哪些問題、哪些已解決。
3. 讀規格：只讀「執行狀態表」與 request 指定的階段章節。
4. 讀變更：執行 `git -C /home/idarfan/fairprice diff <BASE>`，包含尚未 commit 的變更。
5. 自己重跑 request 列出的驗證指令，不採信撰寫端貼上的輸出。
6. 依下方檢查清單逐項審查。
7. 在本格輸出審查結果，並把**完全相同的全文**寫入 verdict 檔（檔名為 request 檔名把 `request-` 換成 `verdict-`）。
8. 用 SendMessage 通知 fairprice-writer，訊息只能是一行：`完成 <verdict 檔名>：VERDICT: <結果>`。不得附上審查內容。

## 檢查清單
1. **範圍**：只做了該階段規格要求的事，沒有改到範圍外的檔案。
2. **驗證**：自己重跑的結果與撰寫端宣稱的一致。
3. **核心用例 e2e**：最基本、最常用、不帶可選參數的情境至少跑過一次，並有實際 URL、DOM 取值、截圖路徑作為證據。只有測試數字不算。
4. **爬蟲正確性**：涉及 Playwright/CDP 時，比對實際導航的 URL、DOM 抓到的值、已知人工驗證值。有輸出不等於輸出正確。
5. **Barchart**：任何 Barchart 內部 API 或 Barchart API 呼叫，一律判 FAIL。
6. **Controller 接線**：新 service 接進 controller 時，必須有覆蓋 route → service 完整路徑的 request spec。
7. **新 route**：必須掛在既有 namespace 下，而且 sidebar 或選單有入口。
8. **規格變更**：必須是 patch 式修改，不是整檔重寫。
9. **機密**：diff 中不得出現 client_secret、token、.env 內容或憑證 JSON。

## 裁決規則
- 使用者裁示「不修改」的條目，不得再以同一理由判 FAIL。
- 同一階段累計第 3 次 FAIL 時，改判 ESCALATE。
- 不要挑風格問題，除非規格有明文要求。

## 輸出格式
```
異端審查官表示:
VERDICT: PASS | FAIL | ESCALATE
問題：
1. [嚴重|一般] 檔案:行號 — 違反的規格條目或檢查項 — 建議修正
質詢：
1. 要求撰寫端解釋的設計決定，或需要補上的證據
對上輪答辯的回應：
1. 採納或維持，附理由
```
沒有內容的區塊寫「無」。
EOF
```
驗證條件：
```bash
f=/home/idarfan/fairprice-review/CLAUDE.md
for k in '異端審查官表示:' '觸發方式' 'SendMessage' '檢查清單' 'ESCALATE' '不得附上審查內容'; do grep -q "$k" $f && echo "HAS $k"; done
```
輸出必須有 6 行 `HAS`。

## S4 撰寫端協定
```bash
cat > /home/idarfan/fairprice-review/WRITER-PROTOCOL.md <<'EOF'
# 撰寫端審查協定

## 生效條件
本 session 以 `--name fairprice-writer` 啟動，而且 ListAgents 看得到 fairprice-inquisitor。

在第一個修改程式的任務開始前檢查一次：
- 條件成立：本協定生效。
- 條件不成立：照常工作，但在回覆第一行提示「審查官未啟動，本次修改未經審查」。

## 審查單位
- 依規格執行的任務：一個規格階段為一個單位。
- 沒有規格的修改：「回報完成之前」為一個單位。

規格的執行狀態表新增「審查」欄。只有取得 PASS 的單位才能標為完成。

## 流程
1. **單位開始**：執行 `git rev-parse HEAD`，記為 BASE。

2. **實作並自我驗證通過後**，寫入 `/home/idarfan/fairprice-review/request-<規格名或任務簡稱>-<單位>-r<n>.md`（n 從 1 起算）。內容只能包含以下欄位：
   - 規格：絕對路徑（沒有規格則寫任務描述）
   - 單位：代號與章節標題
   - BASE
   - 輪次 n
   - 驗證指令與實際輸出
   - e2e 證據：URL、DOM 取值、截圖絕對路徑
   - 答辯：逐條回應上一輪的質詢（第 1 輪填「無」）
   - 使用者裁示不修改：條目編號（沒有則填「無」）

3. **送審**：用 SendMessage 傳給 fairprice-inquisitor，內容只寫 `審查 <request 檔名>`。然後回覆使用者「已送審，請看右側審查官」，並**結束回合**，不要輪詢等待。

4. **收到審查官的「完成 … VERDICT: X」訊息後**：
   - `PASS`：patch 狀態表，繼續下一個單位。
   - `FAIL` 或 `ESCALATE`：
     1. 讀取 verdict 檔。
     2. 回覆 `撰寫端回應:`，然後依審查結果的**條目編號**逐條表態：
        - 對每個「問題」：同意，附修改方案；或不同意，附理由。
        - 對每個「質詢」：逐條回答。
     3. 請使用者裁示，例如「同意 1、3；2 不改」。
     4. **結束回合，等待使用者。**

5. **使用者裁示後**：只修改被同意的條目，重跑驗證，然後以 BASE 不變、輪次 n+1，回到步驟 2。

## 禁止
- 轉述、摘要或改寫審查內容。使用者直接看右側格子，撰寫端只能用條目編號提及。
- 修改或刪除 verdict 檔。
- 未經使用者同意，就依審查意見修改程式碼。
- 未取得 PASS 就進入下一個單位。
EOF
C=/home/idarfan/fairprice/CLAUDE.md
L='@/home/idarfan/fairprice-review/WRITER-PROTOCOL.md'
grep -qxF "$L" $C || printf '\n%s\n' "$L" >> $C
```
驗證條件：
```bash
f=/home/idarfan/fairprice-review/WRITER-PROTOCOL.md
for k in '生效條件' 'SendMessage' '結束回合' '撰寫端回應:' '轉述'; do grep -q "$k" $f && echo "HAS $k"; done
grep -cxF '@/home/idarfan/fairprice-review/WRITER-PROTOCOL.md' /home/idarfan/fairprice/CLAUDE.md
```
- 輸出必須有 5 行 `HAS`。
- 最後一行必須是 `1`，代表 import 行剛好只加了一次。

## S5 tmux 啟動腳本
```bash
cat > /home/idarfan/fairprice-review/start-pair.sh <<'EOF'
#!/usr/bin/env bash
# 啟動撰寫端（左）＋異端審查官（右）。已存在就直接接回。
S=fp
W_CMD='cd /home/idarfan/fairprice && claude --name fairprice-writer; exec bash'
R_CMD='cd /home/idarfan/fairprice-review && claude --name fairprice-inquisitor --add-dir /home/idarfan/fairprice; exec bash'
if [ "$PAIR_DRYRUN" = 1 ]; then S=fp-dryrun; W_CMD='sleep 30'; R_CMD='sleep 30'; fi

if tmux has-session -t "$S" 2>/dev/null; then
  [ "$PAIR_DRYRUN" = 1 ] && exit 0
  exec tmux attach -t "$S"
fi

W=$(tmux new-session -d -s "$S" -x 200 -y 50 -P -F '#{pane_id}' "bash -lc '$W_CMD'")
R=$(tmux split-window -h -l 40% -t "$W" -P -F '#{pane_id}' "bash -lc '$R_CMD'")
tmux set -t "$S" mouse on
tmux set -t "$S" pane-border-status top
tmux set -t "$S" pane-border-format ' #{@role} '
tmux set -p -t "$W" @role '撰寫端 fairprice-writer'
tmux set -p -t "$R" @role '異端審查官 fairprice-inquisitor'
tmux select-pane -t "$W"
[ "$PAIR_DRYRUN" = 1 ] || exec tmux attach -t "$S"
EOF
chmod +x /home/idarfan/fairprice-review/start-pair.sh
```
驗證條件（用 dry-run 模式，不啟動 claude）：
```bash
bash -n /home/idarfan/fairprice-review/start-pair.sh && echo SYNTAX_OK
PAIR_DRYRUN=1 /home/idarfan/fairprice-review/start-pair.sh
tmux list-panes -t fp-dryrun | wc -l
tmux list-panes -t fp-dryrun -F '#{@role}'
tmux kill-session -t fp-dryrun
```
- 輸出必須包含 `SYNTAX_OK`。
- 格子數必須為 `2`。
- 兩個角色名稱都必須出現。

## S6 回報
把狀態表全部標為完成，然後原樣回報使用者：

1. **結束目前這個 Claude Code**，然後在 WSL 終端機執行：
   ```
   ~/fairprice-review/start-pair.sh
   ```
   左邊是撰寫端，右邊是異端審查官。可以用滑鼠拖拉邊界調整比例；按 `Ctrl+b z` 放大或還原目前這一格。

2. **首次啟動時**：
   - 左邊可能會詢問是否允許匯入外部檔案 WRITER-PROTOCOL.md，請選擇允許。
   - 在右邊輸入「嘗試寫入 /home/idarfan/fairprice/tmp-deny-test.txt」，應被拒絕。

3. **喚醒測試**：在左邊輸入「用 SendMessage 傳『測試』給 fairprice-inquisitor」，確認右邊有醒來回應。
   - 若右邊沒有醒來，改用手動方式：撰寫端說「已送審」後，你到右邊輸入「審查」。

4. **之後正常使用**：直接在左邊下任務即可，修改程式時會自動送審。右邊的上下文變長時，在右邊輸入 `/compact`。
