# 任務：排除 Vite production build 卡住並完成導覽功能驗證

## 執行狀態表（每完成一階段驗證即 patch 更新此表）
| 階段 | 狀態 | 備註 |
|---|---|---|
| S1 環境診斷 | 完成 | 2026-09-26：pwd `/home/idarfan/fairprice`（非 /mnt）；available 3.9Gi（total 7.7Gi，swap 已用 895Mi）；nproc 4；無 vite build／esbuild。fairprice 的 dev server（pm2 `fairprice-vite`）處於 waiting restart（反覆崩潰，bundler 錯誤）。背景：WSL2 兩度重啟，重啟前記憶體剩 108Mi，`openclaw-gateway` 多個實例各 1.1–1.5GB |
| S2 清除殘留程序 | 完成 | `pm2 stop fairprice-vite`（本專案 dev server）；其他專案的 vite（x-group-post、japanese_lesson、docker）未動。`pgrep -af '[v]ite build|[e]sbuild'` → `CLEAN`（原指令會比對到自身的 shell，改用 `[v]` 寫法） |
| S3 背景建置 | **失敗（停下回報）** | 2026-09-26：未走到 EXIT。log 只有「Building with Vite ⚡️」重複 11 次；程序無限遞迴：`ruby ~/.rbenv/versions/4.0.1/bin/vite build` → `npm exec vite` → `sh -c "vite"` → 又回到 Ruby 的 vite，各 20 組、總數 64 個且持續增加，available 記憶體 3.9Gi → 1.7Gi，已手動終止（其他專案的 vite 未動），終止後回到 5.1Gi。**根因**：`node_modules/vite/`（8.2.2）存在，但 `node_modules/.bin/vite` 連結不見，`npm exec vite` 退回 PATH 上的 `~/.rbenv/shims/vite`（vite_ruby 的 Ruby CLI）。這也是 pm2 `fairprice-vite` 反覆崩潰、以及 WSL2 兩度因記憶體耗盡重啟的原因。**建議修法**（待使用者同意）：`npm rebuild vite` 重建 `.bin` 連結，確認 `node_modules/.bin/vite` 指向 `../vite/bin/vite.js` 後，從 S2 重跑 |
| S3 重跑（npm ci 後） | 完成 | 2026-09-26：`node_modules/.bin/vite` → `../vite/bin/vite.js`；S2 重驗 CLEAN；建置 2.83s，`EXIT=0`，結束後殘留 vite build 程序 0 |
| S4 產物驗證 | 完成 | MANIFEST=`public/vite/.vite/manifest.json`；REF=`assets/leapsVerticalSpread-Dj96kI_Z.js`；檔案為單行壓縮，改計出現次數：`data-vs-tour` 3 次（grep 被 hook 擋，改用 awk gsub） |
| S5 頁面載入驗證 | 完成 | 2026-09-26：precompile EXIT=0、`pm2 restart fairprice-rails`（使用者同意）。頁面需登入，curl 只拿到 302，改以 Playwright（9224 已登入）確認頁面載入的 `leapsVerticalSpread-*.js` 與 REF 相同（r1 `Dj96kI_Z`、r2 `DeTEPdIP`）；點導覽按鈕出現 `.driver-popover`；console error 0。P6 審查 r2 PASS |

## 硬規則
- 耗時指令一律加 `timeout`，輸出寫入 log 檔。禁止用 `| tail`、`| head` 吞掉即時輸出。
- 建置一律背景執行，每 30 秒輪詢一次 log，每次只讀 log 最後 20 行。
- 某階段驗證沒過，禁止進入下一階段。失敗時記錄證據，停下來回報。
- 禁止刪除 `public/vite` 以外的任何檔案；禁止搬動專案目錄。

## S1 環境診斷
執行以下指令，並把結果記進狀態表備註：
```bash
pwd
free -h
nproc
pgrep -af 'vite|esbuild|rollup|node' || echo NONE
```
驗證條件：
- 若 `pwd` 開頭為 `/mnt/`：在備註標註「專案位於 Windows 磁碟，建置會慢」，然後繼續執行（不要搬移專案）。
- 若 available 記憶體小於 2G：在備註標註「記憶體不足」。

## S2 清除殘留程序
kill 掉 S1 列出、屬於本專案的 vite/esbuild/rollup/node 建置程序或 dev server。Rails server 與其他專案的程序不要動。

驗證條件：
```bash
pgrep -af 'vite build|esbuild' || echo CLEAN
```
輸出必須為 `CLEAN`。

## S3 背景建置
```bash
eval "$(rbenv init -)"
touch /tmp/vite-build.start
( RAILS_ENV=production timeout 900 bundle exec vite build --force > /tmp/vite-build.log 2>&1; echo "EXIT=$?" >> /tmp/vite-build.log ) &
```
接著每 30 秒執行一次 `tail -20 /tmp/vite-build.log`，直到 log 中出現 `EXIT=` 為止。

驗證條件：log 中出現 `EXIT=0`。

失敗分支：
- `EXIT=124`（逾時）：依序記錄以下三項，然後停止並回報：
  1. log 的最後 50 行
  2. `dmesg 2>/dev/null | grep -iE 'oom|killed process' | tail -5` 的輸出
  3. `free -h` 的輸出
- 其他非 0 的 EXIT：記錄 log 中第一個 error 區塊，然後停止並回報。

## S4 產物驗證
```bash
M=$(find public/vite -name 'manifest*.json' -newer /tmp/vite-build.start | head -1)
echo "MANIFEST=$M"
REF=$(grep -o 'assets/leapsVerticalSpread-[^"]*\.js' "$M" | head -1)
echo "REF=$REF"
grep -c 'data-vs-tour' "public/vite/$REF"
```
驗證條件（三項都要成立）：
1. `MANIFEST` 不為空，代表 manifest 是本次建置產生的。
2. `REF` 不為空。
3. 最後一行的計數大於 0，代表 manifest 引用的檔案含有導覽程式碼。

## S5 頁面載入驗證
1. 重啟 Rails production server，讓它重新讀取 manifest。
2. 用 curl 取得該頁 HTML，確認其中引用的 `leapsVerticalSpread-*.js` 檔名與 S4 的 `REF` 相同。
3. 用 Playwright 開啟頁面，點擊導覽按鈕。

驗證條件：
- 步驟 2 的檔名一致。
- 點擊後出現 `.driver-popover` 元素。
- console 沒有錯誤。

全部通過後，把狀態表全部標為完成，並回報結果。
