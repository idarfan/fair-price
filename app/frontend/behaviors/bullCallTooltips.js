/**
 * Bull Call Spread：欄位說明 tooltip 與 9 步全頁導覽。
 *
 * 稽核 H-3 Wave 3：原本內嵌在 app/components/bull_call_spreads/page_component.rb 的 heredoc 裡。
 * 原本用 Ruby 插值寫進來的路由與狀態，改成掛載元素上的 data-config
 * JSON（用 JSON 而不是逐個 data attribute，是為了保留 null 與數值型別，
 * dataset 只能給字串，會把 nil 變成空字串而改變 truthiness）。
 *
 * 稽核 M-6：tooltip 本體與 Bull Put 那支逐字相同，已抽到 shared/colTooltip.js。
 * 留在這裡的只有這一頁獨有的全頁導覽。
 */

import { initColTooltip } from "./shared/colTooltip";

export function init(root) {
  var CFG = JSON.parse(root.dataset.config);

  var tip = initColTooltip({ prefix: "bcvs", colExplain: CFG.colExplain });

  // bcvs.md §導覽與欄位說明規範 B：9 步全頁導覽——步驟數固定 9，
  // 頁面當下不存在的元素直接 filter 掉（不強制報錯），任何階段都能點。
  //
  // 抽出共用核心前，這段是接在欄位 popover 的 else 分支後面（前者以 return
  // 收尾）。改成獨立的 click listener 之後兩者互不干擾：共用核心只處理
  // [data-tip-key]，這裡只處理 #bcvs-tour-btn，同一次點擊不會同時命中。
  document.addEventListener("click", function (e) {
    var tourBtn = e.target.closest("#bcvs-tour-btn");
    if (!tourBtn || !tip.drv()) return;

    var steps = CFG.tourSteps
      .filter(function (s) {
        return document.querySelector(s.el);
      })
      .map(function (s) {
        return {
          element: s.el,
          popover: {
            title: s.title,
            description: s.desc,
            side: "bottom",
            align: "center",
          },
        };
      });
    if (steps.length) {
      tip
        .drv()({
          animate: true,
          allowClose: true,
          overlayOpacity: 0.4,
          showProgress: true,
          steps: steps,
        })
        .drive();
    }
  });
}
