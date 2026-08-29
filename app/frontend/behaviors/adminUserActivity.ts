/**
 * 管理後台：使用者瀏覽軌跡的分頁切換。
 *
 * 稽核 H-3 Wave 2：原本內嵌在 app/components/admin/users/show_component.rb 的 heredoc 裡。
 */

export function init(): void {
  const buttons = document.querySelectorAll<HTMLElement>(".tab-btn");
  const panels: Record<string, HTMLElement | null> = {
    pageviews: document.getElementById("tab-panel-pageviews"),
    commands: document.getElementById("tab-panel-commands"),
  };

  buttons.forEach((btn) => {
    btn.addEventListener("click", () => {
      const target = btn.getAttribute("data-tab-target");
      buttons.forEach((b) => {
        const active = b === btn;
        b.classList.toggle("border-blue-600", active);
        b.classList.toggle("text-blue-600", active);
        b.classList.toggle("border-transparent", !active);
        b.classList.toggle("text-gray-500", !active);
      });
      Object.keys(panels).forEach((key) => {
        panels[key]?.classList.toggle("hidden", key !== target);
      });
    });
  });
}
