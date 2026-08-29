/**
 * 全站字級調整（記在 localStorage）。
 *
 * 需要的資料由掛載元素的 data attribute 傳入：root.dataset.storageKey、root.dataset.sizes
 * （可用字級由 FontSizeControlsComponent::SIZES 決定，前端不再自己寫死一份）。
 *
 * 稽核 H-3 Wave 2：原本內嵌在 app/components/fair_value/font_size_controls_component.rb 的 heredoc 裡。
 * 原本用 Ruby 插值傳進來的值，改成從掛載元素的 data attribute 讀取。
 * TODO：型別化成 .ts。
 */

export function init(root) {
  (function() {
    var KEY = (root.dataset.storageKey || 'fairprice:font-size');
    var ALLOWED = JSON.parse(root.dataset.sizes || '[]');
    if (!ALLOWED.length) return;
    var container = document.getElementById('font-size-controls');
    if (!container) return;
    var btns = container.querySelectorAll('.font-size-btn');

    function applySize(px) {
      document.documentElement.style.fontSize = px + 'px';
      localStorage.setItem(KEY, String(px));
      updateActive(String(px));
    }

    function updateActive(active) {
      btns.forEach(function(b) {
        var isActive = b.getAttribute('data-size') === active;
        b.classList.toggle('text-blue-600', isActive);
        b.classList.toggle('bg-blue-50', isActive);
        b.classList.toggle('text-gray-400', !isActive);
      });
    }

    var stored = localStorage.getItem(KEY);
    updateActive(ALLOWED.indexOf(stored) !== -1 ? stored : ALLOWED[Math.floor(ALLOWED.length / 2)]);

    btns.forEach(function(b) {
      b.addEventListener('click', function() {
        var s = b.getAttribute('data-size');
        if (ALLOWED.indexOf(s) !== -1) applySize(parseInt(s, 10));
      });
    });
  })();
}
