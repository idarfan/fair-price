/**
 * 側邊欄的工具切換下拉選單。
 *
 * 需要的資料由掛載元素的 data attribute 傳入：root.dataset.ddId
 *
 * 稽核 H-3 Wave 2：原本內嵌在 app/components/fair_value/app_switcher_component.rb 的 heredoc 裡。
 */

export function init(root: HTMLElement): void {
  const ddId = root.dataset["ddId"];
  if (!ddId) return;

  const btn = document.getElementById(`${ddId}-btn`);
  const panel = document.getElementById(ddId);
  const chev = document.getElementById(`${ddId}-chevron`);
  if (!btn || !panel) return;

  function open(): void {
    panel!.classList.remove("hidden");
    btn!.setAttribute("aria-expanded", "true");
    // 型別化前 chev 為 null 時這行會拋，選單卻已經展開；只跳過箭頭轉向。
    if (chev) chev.style.transform = "rotate(180deg)";
  }
  function close(): void {
    panel!.classList.add("hidden");
    btn!.setAttribute("aria-expanded", "false");
    if (chev) chev.style.transform = "";
  }
  function toggle(): void {
    if (panel!.classList.contains("hidden")) open();
    else close();
  }

  btn.addEventListener("click", (e) => {
    e.stopPropagation();
    toggle();
  });
  document.addEventListener("click", (e) => {
    // Node#contains 需要 Node；委派事件的 target 可能不是（例如 window）。
    const target = e.target;
    const inside = target instanceof Node && panel.contains(target);
    if (!inside && target !== btn) close();
  });
  document.addEventListener("keydown", (e) => {
    if (e.key === "Escape") close();
  });
}
