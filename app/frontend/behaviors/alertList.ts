/**
 * 到價通知列表：股票 logo 載入失敗的替代圖、拖曳排序。
 * 原本內嵌於 app/components/stock_alert/alert_list_component.rb（稽核 H-3）。
 */
import { csrfHeaders } from "../lib/csrf";

// Sortable 由 layout 以獨立 script 載入，不是 npm 相依，這裡只宣告用到的形狀。
import { initLogoFallback } from "./shared/logoFallback";

interface SortableOptions {
  handle: string;
  animation: number;
  onEnd: () => void;
}
declare const Sortable: { create(el: HTMLElement, options: SortableOptions): void } | undefined;

function initSortable(): void {
  const tbody = document.getElementById("sortable-alerts");
  if (!tbody || typeof Sortable === "undefined") return;

  Sortable.create(tbody, {
    handle: ".drag-handle",
    animation: 150,
    onEnd: () => {
      const ids = Array.from(tbody.querySelectorAll<HTMLElement>("tr[data-alert-id]")).map(
        (row) => row.dataset["alertId"],
      );

      void fetch("/watchlist/reorder", {
        method: "PATCH",
        headers: csrfHeaders({ json: true }),
        body: JSON.stringify({ ids }),
      });
    },
  });
}

export function init(): void {
  initLogoFallback();
  initSortable();
}
