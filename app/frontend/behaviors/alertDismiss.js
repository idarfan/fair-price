/**
 * 提示訊息的關閉按鈕。
 *
 * 稽核 H-3：原本內嵌在 app/components/fair_value/alert_component.rb 的
 * `script { raw ... }` 裡。維持原本的全域 querySelectorAll 語意（同頁多個
 * 提示各自掛載時行為與搬遷前一致）。
 * TODO：型別化成 .ts。
 */

export function init() {
  document.querySelectorAll('[data-dismiss="alert"]').forEach(function (btn) {
    btn.addEventListener('click', function () {
      btn.closest('[data-alert]').remove();
    });
  });
}
