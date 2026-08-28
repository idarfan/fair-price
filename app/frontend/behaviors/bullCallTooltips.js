/**
 * Bull Call Spread：欄位說明 tooltip 與導覽。
 *
 * 稽核 H-3 Wave 3：原本內嵌在 app/components/bull_call_spreads/page_component.rb 的 heredoc 裡。
 * 原本用 Ruby 插值寫進來的路由與狀態，改成掛載元素上的 data-config
 * JSON（用 JSON 而不是逐個 data attribute，是為了保留 null 與數值型別，
 * dataset 只能給字串，會把 nil 變成空字串而改變 truthiness）。
 * TODO：型別化成 .ts；與另一支 spread 頁面之間仍有大量重複（稽核 M-6）。
 */

export function init(root) {
  var CFG = JSON.parse(root.dataset.config);

  (function () {
    var BCVS_COL_EXPLAIN = CFG.colExplain;
    var BCVS_TOUR_STEPS = CFG.tourSteps;

    var tip = document.createElement('div');
    tip.id = 'bcvs-col-tip';
    tip.innerHTML = '<div class="tip-t"></div><div class="tip-b"></div>';
    document.body.appendChild(tip);
    var tT = tip.querySelector('.tip-t'), tB = tip.querySelector('.tip-b');
    function posTip(e) {
      var x = e.clientX + 14, y = e.clientY + 12,
          w = tip.offsetWidth || 280, h = tip.offsetHeight || 100;
      if (x + w > window.innerWidth - 10)  x = e.clientX - w - 10;
      if (y + h > window.innerHeight - 10) y = e.clientY - h - 10;
      tip.style.left = x + 'px'; tip.style.top = y + 'px';
    }
    document.addEventListener('mouseover', function (e) {
      var el = e.target.closest('[data-tip-key]');
      if (el) {
        var d = BCVS_COL_EXPLAIN[el.dataset.tipKey];
        if (!d) return;
        tT.textContent = d.title; tB.textContent = d.desc;
        tip.style.opacity = '1'; posTip(e);
      } else { tip.style.opacity = '0'; }
    });
    document.addEventListener('mousemove', function (e) {
      if (tip.style.opacity !== '0') posTip(e);
    });
    document.addEventListener('mouseout', function (e) {
      if (!e.target.closest('[data-tip-key]')) tip.style.opacity = '0';
    });

    function drv() { return window.driver && window.driver.js && window.driver.js.driver; }
    document.addEventListener('click', function (e) {
      var el = e.target.closest('[data-tip-key]');
      if (el && drv()) {
        var d = BCVS_COL_EXPLAIN[el.dataset.tipKey];
        if (!d) return;
        tip.style.opacity = '0';
        drv()({ animate: true, allowClose: true, overlayOpacity: 0.35,
                steps: [{ element: el, popover: { title: d.title, description: d.desc, side: 'bottom', align: 'center' } }] }).drive();
        return;
      }

      // bcvs.md §導覽與欄位說明規範 B：9 步全頁導覽——步驟數固定 9，
      // 頁面當下不存在的元素直接 filter 掉（不強制報錯），任何階段都能點。
      var tourBtn = e.target.closest('#bcvs-tour-btn');
      if (tourBtn && drv()) {
        var steps = BCVS_TOUR_STEPS
          .filter(function (s) { return document.querySelector(s.el); })
          .map(function (s) {
            return { element: s.el, popover: { title: s.title, description: s.desc, side: 'bottom', align: 'center' } };
          });
        if (steps.length) {
          drv()({ animate: true, allowClose: true, overlayOpacity: 0.4, showProgress: true, steps: steps }).drive();
        }
      }
    });
  })();
}
