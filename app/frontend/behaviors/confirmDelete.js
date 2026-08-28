/**
 * 送出前的刪除確認（表單以 data-confirm-delete 帶訊息）。
 *
 * 稽核 H-3：原本內嵌在 app/views/stock_alerts/index.html.erb 的 <script> 裡。
 * TODO：型別化成 .ts。
 */

export function init() {
  document.addEventListener('submit', function (e) {
    var form = e.target;
    var msg  = form.dataset.confirmDelete;
    if (msg && !confirm(msg)) e.preventDefault();
  });
}
