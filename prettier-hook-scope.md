# prettier-hook-scope.md — 編輯後 hook 不再整檔重排既有 JS

## 問題回報（給使用者）

- **日期時間**：2026-11-10 17:05（Asia/Taipei）
- **症狀**：S2 對 `app/assets/javascripts/leaps_recommendations/vector_pdf.js` 只加 12 行，編輯後 hook 以 prettier 整檔重排，diff 變 427 行；重排版先被 precompile 上線，與 commit 版本不一致，多重啟一次。
- **主訴**：既有未經 prettier 排版的 JS，每次被改都會整檔重排，污染 diff、審查、git blame。

## 找到的問題

1. 編輯後 hook 對被改的 JS 一律 `prettier --write` 整檔。
2. repo 內既有 JS 多數從未以 prettier 排版過，任何小改動都觸發整檔重排。

## 修改策略

prettier 不支援「多段行範圍」排版（`--range-start/--range-end` 只能一段字元區間，且會擴張到整個語句），lint-staged 也是整檔處理，兩者都做不到真正的逐行。改採**依檔案狀態決定**：

| 檔案狀態 | hook 行為 |
|---|---|
| 新檔（HEAD 不存在） | `prettier --write` |
| HEAD 版本已符合 prettier | `prettier --write`（只會動到新改的地方） |
| HEAD 版本不符合 prettier（既有未排版檔） | **跳過 prettier**，只跑 eslint，stderr 印一行說明 |

效果：新程式與已排版檔格式一致；既有未排版檔不再被整檔重排。

## 建議修改順序

S0 定位 hook → S1 改 hook＋測試腳本 → S2 實際編輯驗收。

## 怎麼測試

S1 用暫存 git repo 跑三種狀態；S2 在 FairPrice 實際用 Edit 工具改兩個檔，看 `git diff`。

## 怎麼回報

每階段 patch 狀態表；最終附：hook 檔路徑與 diff、測試腳本輸出、S2 兩個檔的 `git diff --stat`。

---
（以下給 Claude Code）

## 執行狀態表

| 階段 | 內容 | 狀態 | 驗證證據 | 審查 |
|---|---|---|---|---|
| S0 | 定位編輯後 prettier hook | 完成 | 設定：`/home/idarfan/.claude/settings.json:377-381`，PostToolUse matcher `Edit\|Write`、command `/home/idarfan/.claude/hooks/post-edit-ts.sh`、timeout 30。腳本：`/home/idarfan/.claude/hooks/post-edit-ts.sh`（`~/.claude` 為 git repo，HEAD 4085036；該腳本無未 commit 變更）。觸發：第 14 行只處理 `.js/.jsx/.ts/.tsx`（不含 css/json）。prettier 執行（第 19–31 行）：`./node_modules/.bin/prettier --write "$FILE_PATH"`，相對 hook 的 cwd；不存在時 `npx prettier --write`；stderr 丟棄。FairPrice 本地 prettier 3.8.1，無 `.prettierrc`（預設設定）。其後：`.ts/.tsx` 跑 tsc（33–44 行），全部跑 `eslint --fix`（46–54 行），任一失敗 exit 1。現況：`vector_pdf.js` HEAD 版 `prettier --check` exit 1（未排版）；FairPrice 追蹤中的 143 個 js/ts 只有 55 個 HEAD 版已符合 prettier。 | 異端審查官表示: VERDICT: PASS（verdict-prettier-hook-scope-S0-r1.md） |
| S1 | hook 改為依 HEAD 狀態決定＋測試腳本 | 完成 | `/home/idarfan/.claude/hooks/post-edit-ts.sh` 只改第 4 段（prettier）：`git -C <檔案目錄> rev-parse --show-toplevel` 找 repo；不在 repo／HEAD 無此檔／HEAD 版 `prettier --check` 通過 → `--write`；否則跳過並在 stderr 印「[hook] 跳過 prettier：…」。prettier／tsc／eslint 仍照原本以 hook 的 cwd 找 `./node_modules/.bin`，不 cd（S0 質詢 1）。測試 `/home/idarfan/.claude/hooks/test/prettier_scope_test.sh` T1–T4：舊 hook（~/.claude HEAD 4085036）3 過 1 敗（T3 numstat 3/2），新 hook 在 cwd＝fairprice 與 fairprice/app 皆 4/4。npx 替身比對：兩種 cwd 下新舊 hook 用的 prettier 相同（根目錄 `./node_modules/.bin/prettier`、app 子目錄 `npx prettier`）。shellcheck 0。**偏離虛擬碼的 `cd <repo 根目錄>`**：改用 `git -C "$REPO_ROOT"` 讀 HEAD、cwd 不變，讓 prettier／tsc／eslint 找法與原 hook 相同，理由與實測見 verdict-prettier-hook-scope-S1-r1.md，勿照虛擬碼改回 cd。 | 異端審查官表示: VERDICT: PASS（verdict-prettier-hook-scope-S1-r1.md） |
| S2 | 實際編輯驗收 | 完成 | 步驟 1–2：Edit 工具在 `vector_pdf.js` 檔尾加 `// prettier-hook-scope 驗收` → `git diff --stat` `1 file changed, 1 insertion(+)`、numstat 1/0；Edit 後無「PostToolUse hook modified」提示；以同一 stdin JSON 重跑 hook 取 stderr：「[hook] 跳過 prettier：app/assets/javascripts/leaps_recommendations/vector_pdf.js 的 HEAD 版本未經 prettier 排版（避免整檔重排）」，exit 0。步驟 3：`git checkout` 還原。步驟 4（patch1）：`prettier --file-info app/assets/javascripts/prettier_scope_probe.js` → `"ignored": false`；Write 未排版內容後被排版成 prettier 輸出（`var probe = "unformatted";`…，diff 相同），HEAD 無此檔（cat-file 128），已刪除。原 `tmp/` 路徑因 `.gitignore:12` 被 prettier 忽略（新舊 hook 皆不排版），經使用者 patch1 改路徑。`git status --short` 只剩既有的 ` M docs/architecture_spec.yml`、` M docs/fairprice-architecture.html`、` M docs/fairprice-architecture.svg`（已追蹤、未 commit 的修改，非 untracked）。 | 異端審查官表示: VERDICT: PASS（verdict-prettier-hook-scope-S2-r1.md） |

規則：驗證未過禁止進入下一階段；每階段過驗證立即 patch 本表；接續 session 只讀本表＋進行中階段。每階段完成交審查官，審查欄填「異端審查官表示:」結論後才算完成。

## 全域限制

- 只改負責 prettier 的那段 hook，其他 hook（含禁止 `sed -n` 等）不動。
- 不修改任何既有 JS 的內容或格式；不新增 `.prettierignore` 項目。
- hook 在 repo 外時，規格與回報一律寫絕對路徑。

## S0 定位

動作：
1. `grep -rn "prettier" ~/.claude/settings.json ~/.claude/hooks/ /home/idarfan/fairprice/.claude/ 2>/dev/null` 找出 PostToolUse（Edit／Write）呼叫 prettier 的設定與腳本。
2. 記錄：設定檔絕對路徑、腳本絕對路徑、觸發條件（matcher、副檔名）、目前執行的完整指令、prettier 執行方式（`npx`／本地 binary 版本）。
3. 確認同一 hook 是否也處理 `.ts`、`.css`、`.json` 等其他副檔名。

驗證：列出的路徑 `test -f` 成功；`grep -n prettier <腳本>` 命中記錄的行號。

## S1 修改 hook

邏輯（套用於 S0 找到的所有 prettier 處理副檔名）：

```
f=<被編輯檔的絕對路徑>
cd <f 所在 git repo 根目錄>   # 不在 git repo → 維持原行為（整檔 prettier）
rel=<f 相對 repo 根的路徑>
if ! git cat-file -e HEAD:"$rel" 2>/dev/null; then
  prettier --write "$f"                                  # 新檔
elif git show HEAD:"$rel" | prettier --check --stdin-filepath "$f" >/dev/null 2>&1; then
  prettier --write "$f"                                  # HEAD 已排版
else
  echo "[hook] 跳過 prettier：$rel 的 HEAD 版本未經 prettier 排版（避免整檔重排）" >&2
fi
# eslint 照原 hook 行為執行，不受上述分支影響
```

- prettier 使用 S0 記錄的同一執行方式與設定檔。
- 跳過時 hook 結束碼為 0（non-blocking）。

測試腳本：新增 `~/.claude/hooks/test/prettier_scope_test.sh`（或 S0 找到的 hook 目錄下 `test/`），在 `mktemp -d` 建暫存 git repo，跑三案：

| 案例 | 準備 | 編輯 | 預期 |
|---|---|---|---|
| T1 新檔 | 不 commit | 寫入未排版內容 | 檔案被 prettier 排版 |
| T2 已排版檔 | commit 一個 prettier 排版過的檔 | 加一行未排版程式 | 只有新增那行被排版，`git diff --numstat` 新增行數 = 實際新增行數 |
| T3 未排版既有檔 | commit 一個未排版檔（例：單引號、無分號、縮排 4） | 加一行 | 檔案除新增行外與 HEAD 完全相同；stderr 含「跳過 prettier」 |

另一案 T4：檔案不在 git repo → 維持原行為（整檔排版）。

驗證：測試腳本 4 案全過，輸出存證據；T3 必須在**舊 hook** 下失敗（先跑舊版確認失敗，再換新版），送審附兩次輸出。

## S2 實際編輯驗收

在 `/home/idarfan/fairprice`：
1. 用 Edit 工具在 `app/assets/javascripts/leaps_recommendations/vector_pdf.js` 檔尾加一行註解 `// prettier-hook-scope 驗收`。
2. `git diff --stat` 該檔必須是 `1 insertion`；stderr 有「跳過 prettier」。
3. `git checkout -- <該檔>` 還原。
4. 新建 `app/assets/javascripts/prettier_scope_probe.js`（未納版控、不在 `.gitignore`、新檔），先以 `prettier --file-info` 確認 `"ignored": false`，寫入未排版內容 → 確認被排版 → 立即刪除。

驗證：步驟 2 的 `--stat` 輸出、步驟 4 的 `--file-info` 輸出與排版前後內容附證據；`git status` 回到乾淨狀態（既有 docs/ 3 個「已追蹤、有未 commit 修改」的檔除外，逐一列名）。

不需重啟 server（未改 app 程式）。
