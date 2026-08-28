/**
 * 管理後台：使用者瀏覽軌跡圖表。
 *
 * 稽核 H-3 Wave 2：原本內嵌在 app/components/admin/users/show_component.rb 的 heredoc 裡。
 * 原本用 Ruby 插值傳進來的值，改成從掛載元素的 data attribute 讀取。
 * TODO：型別化成 .ts。
 */

export function init(root) {
  (function () {
    var buttons = document.querySelectorAll('.tab-btn');
    var panels = { pageviews: document.getElementById('tab-panel-pageviews'), commands: document.getElementById('tab-panel-commands') };

    buttons.forEach(function (btn) {
      btn.addEventListener('click', function () {
        var target = btn.getAttribute('data-tab-target');
        buttons.forEach(function (b) {
          var active = b === btn;
          b.classList.toggle('border-blue-600', active);
          b.classList.toggle('text-blue-600', active);
          b.classList.toggle('border-transparent', !active);
          b.classList.toggle('text-gray-500', !active);
        });
        Object.keys(panels).forEach(function (key) {
          if (panels[key]) panels[key].classList.toggle('hidden', key !== target);
        });
      });
    });
  })();
}
