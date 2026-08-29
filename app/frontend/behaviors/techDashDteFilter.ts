/**
 * 技術面儀表板：DTE 分層篩選。
 *
 * 稽核 H-3 Wave 2：原本內嵌在 app/components/technical_dashboard/page_component.rb 的 heredoc 裡。
 */

export function init(): void {
  const btn = document.getElementById("dte-filter-btn");
  if (!btn) return;
  let active = false;

  function applyDisplay(): void {
    const rows = Array.from(document.querySelectorAll<HTMLElement>("tr[data-rank]"));
    let visible = 0;
    rows.forEach((row) => {
      // dataset 缺值時 parseInt 得到 NaN，與型別化前的行為一致
      // （NaN !== 0 為真，所以那一列照常顯示）。
      const dte = parseInt(row.dataset["dte"] ?? "", 10);
      const show = (!active || dte !== 0) && visible < 20;
      if (show) visible++;
      row.style.display = show ? "" : "none";
    });
  }

  applyDisplay();

  btn.addEventListener("click", () => {
    active = !active;
    btn.textContent = active ? "全部顯示" : "排除 DTE=0";
    btn.classList.toggle("bg-purple-100", active);
    btn.classList.toggle("border-purple-500", active);
    btn.classList.toggle("text-purple-700", active);
    applyDisplay();
  });
}
