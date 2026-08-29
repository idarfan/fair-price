/**
 * Daily Momentum：觀察清單的新增/編輯/排序。
 *
 * 稽核 H-3：原本內嵌在 app/components/daily_momentum/watchlist_manager_component.rb 的 heredoc 裡。
 * Sortable 由 layout 以獨立 <script> 從 CDN 載入（型別見 types/globals.d.ts）。
 */

import { closestFrom, csrfToken } from "./shared/dom";

export function init(): void {
  // ── 股票 logo fallback ─────────────────────────────────────────
  document.querySelectorAll<HTMLImageElement>(".stock-logo").forEach((img) => {
    img.addEventListener("error", () => {
      const fallbackSrc = img.dataset["fallback"];
      if (fallbackSrc && img.src !== fallbackSrc) {
        img.src = fallbackSrc;
      } else {
        img.style.display = "none";
        const span = img.nextElementSibling;
        if (span instanceof HTMLElement) span.style.display = "flex";
      }
    });
  });

  // ── 拖曳排序 ───────────────────────────────────────────────────
  const el = document.getElementById("watchlist-sortable");
  if (el && typeof Sortable !== "undefined") {
    Sortable.create(el, {
      handle: ".drag-handle",
      animation: 150,
      ghostClass: "bg-blue-50",
      onEnd: () => {
        const ids = Array.from(el.querySelectorAll<HTMLElement>("tr[data-id]"))
          .map((tr) => tr.dataset["id"]);
        void fetch("/momentum/watchlist/reorder", {
          method: "PATCH",
          headers: {
            "Content-Type": "application/json",
            "X-CSRF-Token": csrfToken(),
          },
          body: JSON.stringify({ ids }),
        });
      },
    });
  }

  // ── 編輯／取消（事件委派）──────────────────────────────────────
  document.addEventListener("click", (e) => {
    const startBtn = closestFrom(e, "[data-start-edit]");
    if (startBtn) {
      const id = startBtn.dataset["startEdit"];
      document.getElementById(`view-${id}`)?.classList.add("hidden");
      const form = document.getElementById(`edit-form-${id}`);
      if (!form) return;
      form.classList.remove("hidden");
      const inp = form.querySelector('input[name="symbol"]');
      if (inp instanceof HTMLInputElement) { inp.focus(); inp.select(); }
      return;
    }

    const cancelBtn = closestFrom(e, "[data-cancel-edit]");
    if (cancelBtn) {
      const id = cancelBtn.dataset["cancelEdit"];
      document.getElementById(`view-${id}`)?.classList.remove("hidden");
      document.getElementById(`edit-form-${id}`)?.classList.add("hidden");
      return;
    }

    // 刪除確認
    const delBtn = closestFrom<HTMLButtonElement>(e, "button[data-confirm]");
    if (delBtn) {
      e.preventDefault();
      const message = delBtn.dataset["confirm"];
      if (message !== undefined && confirm(message)) {
        delBtn.disabled = true;
        delBtn.style.opacity = "0.4";
        const form = delBtn.closest("form");
        if (form instanceof HTMLFormElement) form.submit();
      }
    }
  });
}
