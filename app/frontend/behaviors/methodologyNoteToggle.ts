/**
 * 估值方法說明的展開/收合。
 *
 * 需要的資料由掛載元素的 data attribute 傳入：root.dataset.uid
 *
 * 稽核 H-3 Wave 2：原本內嵌在 app/components/fair_value/methodology_note_component.rb 的 heredoc 裡。
 * 原本用 Ruby 插值傳進來的值，改成從掛載元素的 data attribute 讀取。
 */

export function init(root: HTMLElement): void {
  const uid = root.dataset["uid"];
  if (!uid) return;

  const btn = document.querySelector(`[data-toggle="${uid}"]`);
  const panel = document.getElementById(uid);
  const icon = document.getElementById(`${uid}-icon`);
  if (!btn || !panel) return;

  btn.addEventListener("click", () => {
    const hidden = panel.classList.toggle("hidden");
    // 型別化前 icon 為 null 時這行會拋，但開合本身已經完成。保留開合、
    // 只跳過圖示更新，比讓整個 handler 中斷合理。
    if (icon) icon.textContent = hidden ? "▼" : "▲";
  });
}
