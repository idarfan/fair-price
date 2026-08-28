/**
 * 側邊欄的工具切換下拉選單。
 *
 * 需要的資料由掛載元素的 data attribute 傳入：root.dataset.ddId
 *
 * 稽核 H-3 Wave 2：原本內嵌在 app/components/fair_value/app_switcher_component.rb 的 heredoc 裡。
 * 原本用 Ruby 插值傳進來的值，改成從掛載元素的 data attribute 讀取。
 * TODO：型別化成 .ts。
 */

export function init(root) {
  (function() {
    var btn   = document.getElementById(root.dataset.ddId + '-btn');
    var panel = document.getElementById(root.dataset.ddId);
    var chev  = document.getElementById(root.dataset.ddId + '-chevron');
    if (!btn || !panel) return;

    function open() {
      panel.classList.remove('hidden');
      btn.setAttribute('aria-expanded', 'true');
      chev.style.transform = 'rotate(180deg)';
    }
    function close() {
      panel.classList.add('hidden');
      btn.setAttribute('aria-expanded', 'false');
      chev.style.transform = '';
    }
    function toggle() { panel.classList.contains('hidden') ? open() : close(); }

    btn.addEventListener('click', function(e) { e.stopPropagation(); toggle(); });
    document.addEventListener('click', function(e) {
      if (!panel.contains(e.target) && e.target !== btn) close();
    });
    document.addEventListener('keydown', function(e) {
      if (e.key === 'Escape') close();
    });
  })();
}
