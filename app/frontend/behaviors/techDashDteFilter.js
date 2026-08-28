/**
 * 技術面儀表板：DTE 分層篩選。
 *
 * 稽核 H-3 Wave 2：原本內嵌在 app/components/technical_dashboard/page_component.rb 的 heredoc 裡。
 * 原本用 Ruby 插值傳進來的值，改成從掛載元素的 data attribute 讀取。
 * TODO：型別化成 .ts。
 */

export function init(root) {
  (function () {
    var btn = document.getElementById('dte-filter-btn');
    if (!btn) return;
    var active = false;

    function applyDisplay() {
      var rows = Array.from(document.querySelectorAll('tr[data-rank]'));
      var visible = 0;
      rows.forEach(function (row) {
        var dte  = parseInt(row.dataset.dte, 10);
        var show = (!active || dte !== 0) && visible < 20;
        if (show) visible++;
        row.style.display = show ? '' : 'none';
      });
    }

    applyDisplay();

    btn.addEventListener('click', function () {
      active = !active;
      btn.textContent = active ? '全部顯示' : '排除 DTE=0';
      btn.classList.toggle('bg-purple-100',    active);
      btn.classList.toggle('border-purple-500', active);
      btn.classList.toggle('text-purple-700',  active);
      applyDisplay();
    });
  })();
}
