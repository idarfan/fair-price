/**
 * 送出前的刪除確認（表單以 data-confirm-delete 帶訊息）。
 *
 * 稽核 H-3：原本內嵌在 app/views/stock_alerts/index.html.erb 的 <script> 裡。
 */

export function init(): void {
  document.addEventListener("submit", (e) => {
    // Event#target 的型別是 EventTarget，沒有 dataset；委派事件的 target 也
    // 可能不是表單。型別化前是直接讀 e.target.dataset，非表單會拋 TypeError。
    const form = e.target;
    if (!(form instanceof HTMLFormElement)) return;

    const msg = form.dataset["confirmDelete"];
    if (msg && !confirm(msg)) e.preventDefault();
  });
}
