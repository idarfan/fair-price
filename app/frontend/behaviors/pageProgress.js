/**
 * 換頁進度條（NProgress）。
 *
 * 稽核 H-3：原本內嵌在 app/views/layouts/application.html.erb 的 <script> 裡。
 * NProgress 本身由 layout 以獨立 <script src> 從 CDN 載入，是全域變數。
 * TODO：型別化成 .ts。
 */

export function init() {
  NProgress.configure({ showSpinner: false, speed: 300, minimum: 0.15 });
  document.addEventListener('DOMContentLoaded', function () {
    NProgress.done();
    document.addEventListener('click', function (e) {
      var link = e.target.closest('a[href]');
      if (!link) return;
      var href = link.getAttribute('href');
      if (!href || href.startsWith('#') || href.startsWith('javascript') || link.target === '_blank') return;
      NProgress.start(); NProgress.set(0.4);
    });
    document.addEventListener('submit', function () {
      NProgress.start(); NProgress.set(0.4);
    });
  });
}
