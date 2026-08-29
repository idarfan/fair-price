/**
 * 提示訊息的關閉按鈕。
 *
 * 稽核 H-3：原本內嵌在 app/components/fair_value/alert_component.rb 的
 * `script { raw ... }` 裡。維持原本的全域 querySelectorAll 語意（同頁多個
 * 提示各自掛載時行為與搬遷前一致）。
 */

export function init(): void {
  document.querySelectorAll('[data-dismiss="alert"]').forEach((btn) => {
    btn.addEventListener("click", () => {
      // 型別化前這裡是 btn.closest(...).remove()，closest 回傳 null 時會拋
      // TypeError。按鈕永遠渲染在 [data-alert] 容器內，所以那個 null 分支
      // 實務上不會發生；改用 optional chaining 保留同樣的成功路徑。
      btn.closest("[data-alert]")?.remove();
    });
  });
}
