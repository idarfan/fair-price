/**
 * 估值方法說明的展開/收合。
 *
 * 需要的資料由掛載元素的 data attribute 傳入：root.dataset.uid
 *
 * 稽核 H-3 Wave 2：原本內嵌在 app/components/fair_value/methodology_note_component.rb 的 heredoc 裡。
 * 原本用 Ruby 插值傳進來的值，改成從掛載元素的 data attribute 讀取。
 * TODO：型別化成 .ts。
 */

export function init(root) {
  (function() {
    var btn = document.querySelector('[data-toggle="' + root.dataset.uid + '"]');
    var panel = document.getElementById(root.dataset.uid);
    var icon = document.getElementById(root.dataset.uid + '-icon');
    if (!btn || !panel) return;
    btn.addEventListener('click', function() {
      var hidden = panel.classList.toggle('hidden');
      icon.textContent = hidden ? '▼' : '▲';
    });
  })();
}
