/**
 * 更新說明彈窗的開關。
 *
 * 稽核 H-3：原本內嵌在 app/views/layouts/application.html.erb 的 <script> 裡。
 * TODO：型別化成 .ts。
 */

export function init() {
  var overlay = document.getElementById('release-notes-overlay');
  var openBtn = document.getElementById('release-notes-btn');
  if (!overlay || !openBtn) return;
  function open() { overlay.classList.remove('hidden'); }
  function close() { overlay.classList.add('hidden'); }
  openBtn.addEventListener('click', open);
  document.getElementById('release-notes-close').addEventListener('click', close);
  document.getElementById('release-notes-close-2').addEventListener('click', close);
  overlay.addEventListener('click', function (e) { if (e.target === overlay) close(); });
  document.addEventListener('keydown', function (e) {
    if (e.key === 'Escape' && !overlay.classList.contains('hidden')) close();
  });
}
