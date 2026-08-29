/**
 * Bull Put Spread：欄位說明 tooltip。
 *
 * 稽核 H-3 Wave 3：原本內嵌在 app/components/bull_put_spreads/page_component.rb 的 heredoc 裡。
 * 原本用 Ruby 插值寫進來的路由與狀態，改成掛載元素上的 data-config
 * JSON（用 JSON 而不是逐個 data attribute，是為了保留 null 與數值型別，
 * dataset 只能給字串，會把 nil 變成空字串而改變 truthiness）。
 *
 * 稽核 M-6：tooltip 本體與 Bull Call 那支逐字相同，已抽到 shared/colTooltip.js。
 * 這支頁面沒有額外的導覽行為，所以就是一行轉呼叫。
 */

import { initColTooltip } from "./shared/colTooltip";

export function init(root) {
  var CFG = JSON.parse(root.dataset.config);

  initColTooltip({ prefix: "bpus", colExplain: CFG.colExplain });
}
