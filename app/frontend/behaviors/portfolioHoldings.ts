/**
 * 投資組合持股列表：即時報價、損益試算、拖曳排序。
 *
 * 稽核 H-3：原本內嵌在 app/components/portfolio/holding_list_component.rb 的 heredoc 裡。
 * Sortable 由 layout 以獨立 <script> 從 CDN 載入（型別見 types/globals.d.ts）。
 */

import { closestFrom, csrfToken } from "./shared/dom";
import { isRecord, num } from "./shared/json";

interface Quote {
  c?: number;
  d?: number;
  dp?: number;
}

/** /portfolio/quotes 的回應：{ SYMBOL: { c, d, dp } }。用 type predicate 收窄。 */
function parseQuotes(payload: unknown): Record<string, Quote> {
  if (!isRecord(payload)) return {};
  const out: Record<string, Quote> = {};
  for (const [symbol, raw] of Object.entries(payload)) {
    if (!isRecord(raw)) continue;
    const quote: Quote = {};
    const c = num(raw, "c");
    if (c !== undefined) quote.c = c;
    const d = num(raw, "d");
    if (d !== undefined) quote.d = d;
    const dp = num(raw, "dp");
    if (dp !== undefined) quote.dp = dp;
    out[symbol] = quote;
  }
  return out;
}

export function init(): void {
  // ── OCR 匯入的載入狀態 ─────────────────────────────────────────
  const ocrForm = document.querySelector('form[action="/portfolio/ocr_import"]');
  ocrForm?.addEventListener("submit", () => {
    const btn = document.getElementById("ocr-submit-btn");
    const loading = document.getElementById("ocr-loading");
    if (btn instanceof HTMLButtonElement) {
      btn.disabled = true;
      btn.classList.add("opacity-50");
    }
    loading?.classList.remove("hidden");
  });

  // ── 股票 logo fallback ─────────────────────────────────────────
  document.querySelectorAll<HTMLImageElement>(".stock-logo").forEach((img) => {
    img.addEventListener("error", () => {
      const fb = img.dataset["fallback"];
      if (fb && img.src !== fb) {
        img.src = fb;
      } else {
        img.style.display = "none";
        const span = img.nextElementSibling;
        if (span instanceof HTMLElement) span.style.display = "flex";
      }
    });
  });

  // ── 拖曳排序 ───────────────────────────────────────────────────
  const tbody = document.getElementById("sortable-portfolio");
  if (tbody && typeof Sortable !== "undefined") {
    Sortable.create(tbody, {
      handle: ".drag-handle",
      animation: 150,
      ghostClass: "bg-blue-50",
      onEnd: () => {
        const ids = Array.from(tbody.querySelectorAll<HTMLElement>("tr[data-id]"))
          .map((tr) => tr.dataset["id"]);
        void fetch("/portfolio/reorder", {
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

  // ── 刪除確認 ───────────────────────────────────────────────────
  document.addEventListener("click", (e) => {
    const btn = closestFrom(e, 'button[type="submit"]');
    if (!btn) return;
    const form = btn.closest("form");
    const msg = form instanceof HTMLFormElement ? form.dataset["confirmDelete"] : undefined;
    if (msg && !confirm(msg)) e.preventDefault();
  });

  // ── 即時報價輪詢（每 60 秒）────────────────────────────────────
  function fmtCurrency(v: number | null | undefined): string {
    if (v == null) return "—";
    return `$${v.toLocaleString("en-US", { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
  }
  function flash(el: HTMLElement): void {
    el.style.transition = "background 0.3s";
    el.style.background = "#fef9c3";
    setTimeout(() => { el.style.background = ""; }, 800);
  }
  function applyQuotes(quotes: Record<string, Quote>): void {
    document.querySelectorAll<HTMLElement>("tr[data-id]").forEach((row) => {
      const id = row.dataset["id"];
      const shares = parseFloat(row.dataset["shares"] ?? "");
      const unitCost = parseFloat(row.dataset["unitCost"] ?? "");
      const totalCost = unitCost * shares;
      const sym = row.querySelector("span.font-mono")?.textContent?.trim();
      if (!sym) return;
      const q = quotes[sym];
      if (!q) return;
      const { c, d, dp } = q;

      const priceCell = document.getElementById(`cell-price-${id}`);
      if (priceCell && c !== undefined && c > 0) {
        priceCell.innerHTML =
          `<span class="font-semibold text-gray-900 text-xs">${fmtCurrency(c)}</span>`;
        flash(priceCell);
      }
      const dCell = document.getElementById(`cell-changed-${id}`);
      if (dCell && d != null) {
        const dc = d >= 0 ? "text-green-600" : "text-red-600";
        dCell.innerHTML = `<span class="text-xs ${dc}">${d >= 0 ? "+" : ""}${fmtCurrency(d)}</span>`;
        flash(dCell);
      }
      const dpCell = document.getElementById(`cell-changedp-${id}`);
      if (dpCell && dp != null) {
        const dpc = dp >= 0 ? "text-green-600" : "text-red-600";
        dpCell.innerHTML =
          `<span class="text-xs font-medium ${dpc}">${dp >= 0 ? "+" : ""}${dp.toFixed(2)}%</span>`;
        flash(dpCell);
      }
      const mktCell = document.getElementById(`cell-mktval-${id}`);
      if (mktCell && c !== undefined && c > 0) {
        mktCell.innerHTML = `<span class="text-xs">${fmtCurrency(c * shares)}</span>`;
        flash(mktCell);
      }
      const pnlCell = document.getElementById(`cell-pnl-${id}`);
      if (pnlCell && c !== undefined && c > 0) {
        const pnl = c * shares - totalCost;
        const pc = pnl >= 0 ? "text-green-600" : "text-red-500";
        pnlCell.innerHTML =
          `<span class="text-xs ${pc}">${pnl >= 0 ? "+" : ""}${fmtCurrency(pnl)}</span>`;
        flash(pnlCell);
      }
      const pnlPctCell = document.getElementById(`cell-pnlpct-${id}`);
      if (pnlPctCell && c !== undefined && c > 0 && totalCost > 0) {
        const pnlPct = (c * shares - totalCost) / totalCost * 100;
        const ppc = pnlPct >= 0 ? "text-green-600" : "text-red-500";
        pnlPctCell.innerHTML =
          `<span class="text-xs ${ppc}">${pnlPct >= 0 ? "+" : ""}${pnlPct.toFixed(2)}%</span>`;
        flash(pnlPctCell);
      }
    });
  }
  function pollQuotes(): void {
    fetch("/portfolio/quotes")
      .then((r) => r.json())
      .then((data: unknown) => { applyQuotes(parseQuotes(data)); })
      .catch(() => {});
  }
  setInterval(pollQuotes, 60000);

  // ── 獲利 ↔ 賣出價雙向試算 ──────────────────────────────────────
  document.querySelectorAll<HTMLInputElement>("input[data-holding-id]").forEach((profitInput) => {
    const id = profitInput.dataset["holdingId"];
    const unitCost = parseFloat(profitInput.dataset["unitCost"] ?? "");
    const shares = parseFloat(profitInput.dataset["shares"] ?? "");
    const sellEl = document.getElementById(`sell-price-${id}`);
    if (!(sellEl instanceof HTMLInputElement) || !shares) return;

    profitInput.addEventListener("input", () => {
      const profit = parseFloat(profitInput.value);
      if (!isNaN(profit)) {
        sellEl.value = (unitCost + profit / shares).toFixed(2);
        profitInput.className = profitInput.className.replace(/text-(green|red)-\d+/g, "");
        profitInput.classList.add(profit >= 0 ? "text-green-600" : "text-red-500");
      } else {
        sellEl.value = "";
      }
    });

    sellEl.addEventListener("input", () => {
      const sell = parseFloat(sellEl.value);
      if (!isNaN(sell)) {
        const profit = (sell - unitCost) * shares;
        profitInput.value = profit.toFixed(2);
        profitInput.className = profitInput.className.replace(/text-(green|red)-\d+/g, "");
        profitInput.classList.add(profit >= 0 ? "text-green-600" : "text-red-500");
      } else {
        profitInput.value = "";
      }
    });
  });
}
