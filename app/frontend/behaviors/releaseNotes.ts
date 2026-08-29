/**
 * 更新說明彈窗的開關。
 *
 * 稽核 H-3：原本內嵌在 app/views/layouts/application.html.erb 的 <script> 裡。
 */

export function init(): void {
  const overlay = document.getElementById("release-notes-overlay");
  const openBtn = document.getElementById("release-notes-btn");
  if (!overlay || !openBtn) return;

  const open = (): void => overlay.classList.remove("hidden");
  const close = (): void => overlay.classList.add("hidden");

  openBtn.addEventListener("click", open);
  // 型別化前這兩行直接對 getElementById 的結果掛 listener，元素不存在會拋。
  // 兩顆關閉鈕都在同一段 layout 標記裡，缺一顆時讓另一顆照常運作即可。
  document.getElementById("release-notes-close")?.addEventListener("click", close);
  document.getElementById("release-notes-close-2")?.addEventListener("click", close);

  overlay.addEventListener("click", (e) => {
    if (e.target === overlay) close();
  });
  document.addEventListener("keydown", (e) => {
    if (e.key === "Escape" && !overlay.classList.contains("hidden")) close();
  });
}
