/**
 * Daily Momentum：新聞分頁切換與載入。
 *
 * 稽核 H-3：原本內嵌在 app/components/daily_momentum/news_tab_panel_component.rb 的 heredoc 裡。
 */

import { closestFrom } from "./shared/dom";
import { arr, isRecord } from "./shared/json";

interface NewsItem {
  headline: string;
  content_html?: string;
  datetime?: string;
  source?: string;
  url?: string;
}

/** 後端回傳的 news 陣列；用 type predicate 收窄，不用 `as`。 */
function parseNews(payload: unknown): NewsItem[] {
  return arr(payload, "news").flatMap((raw): NewsItem[] => {
    if (!isRecord(raw)) return [];
    const headline = raw["headline"];
    if (typeof headline !== "string") return [];
    const item: NewsItem = { headline };
    const html = raw["content_html"];
    if (typeof html === "string") item.content_html = html;
    const dt = raw["datetime"];
    if (typeof dt === "string") item.datetime = dt;
    const src = raw["source"];
    if (typeof src === "string") item.source = src;
    const url = raw["url"];
    if (typeof url === "string") item.url = url;
    return [item];
  });
}

export function init(): void {
  const loaded: Record<string, boolean> = {};

  // ── 點代號 → 載入新聞 ──────────────────────────────────────────
  document.addEventListener("click", (e) => {
    const btn = closestFrom(e, "[data-fetch-news]");
    if (!btn) return;
    const symbol = btn.dataset["fetchNews"];
    if (!symbol) return;
    activateOrLoad(symbol);
  });

  function activateOrLoad(symbol: string): void {
    if (loaded[symbol]) { activateTab(symbol); return; }
    createTab(symbol);
    fetchNews(symbol);
  }

  // ── 建立分頁 ───────────────────────────────────────────────────
  function createTab(symbol: string): void {
    const bar = document.getElementById("news-tab-bar");
    const contents = document.getElementById("news-tab-contents");
    if (!bar || !contents) return;
    document.getElementById("news-placeholder")?.classList.add("hidden");
    bar.classList.remove("hidden");

    const initials = symbol.slice(0, 2);
    const tab = document.createElement("button");
    tab.type = "button";
    tab.id = `ntab-${symbol}`;
    tab.className = "ntab inline-flex items-center gap-1.5 px-4 py-2.5 text-xs font-mono font-semibold border-b-2 border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300 -mb-px transition-colors whitespace-nowrap";
    tab.innerHTML =
      '<span class="relative flex-shrink-0 w-5 h-5">'
        + '<img class="tab-logo w-5 h-5 rounded-full object-contain bg-white border border-gray-100"'
             + ` src="https://assets.parqet.com/logos/symbol/${symbol}?format=jpg"`
             + ` data-fallback="https://static2.finnhub.io/file/publicdatany/finnhubimage/stock_logo/${symbol}.png"`
             + ` alt="${symbol}">`
        + `<span class="tab-logo-fallback hidden absolute inset-0 rounded-full bg-gray-800 text-white text-[8px] font-bold items-center justify-center">${initials}</span>`
      + "</span>"
      + `<span>${symbol}</span>`;

    const logo = tab.querySelector(".tab-logo");
    if (logo instanceof HTMLImageElement) {
      logo.addEventListener("error", () => {
        const fb = logo.dataset["fallback"];
        if (fb && logo.src !== fb) {
          logo.src = fb;
        } else {
          // 與 shared/logoFallback 相同的做法：改切 class，不混用 inline style。
          logo.classList.add("hidden");
          const next = logo.nextElementSibling;
          if (next instanceof HTMLElement) {
            next.classList.remove("hidden");
            next.classList.add("flex");
          }
        }
      });
    }
    tab.addEventListener("click", () => { activateTab(symbol); });
    bar.appendChild(tab);

    const panel = document.createElement("div");
    panel.id = `npanel-${symbol}`;
    panel.className = "npanel hidden divide-y divide-gray-100";
    panel.innerHTML = '<div class="py-10 text-center text-gray-400 text-sm">載入中…</div>';
    contents.appendChild(panel);

    activateTab(symbol);
  }

  // ── 切換分頁 ───────────────────────────────────────────────────
  function activateTab(symbol: string): void {
    document.querySelectorAll(".ntab").forEach((t) => {
      t.classList.remove("border-blue-600", "text-blue-700");
      t.classList.add("border-transparent", "text-gray-500");
    });
    const tab = document.getElementById(`ntab-${symbol}`);
    if (tab) {
      tab.classList.remove("border-transparent", "text-gray-500");
      tab.classList.add("border-blue-600", "text-blue-700");
    }

    document.querySelectorAll(".npanel").forEach((p) => { p.classList.add("hidden"); });
    document.getElementById(`npanel-${symbol}`)?.classList.remove("hidden");

    document.getElementById("stock-news-panel")
      ?.scrollIntoView({ behavior: "smooth", block: "nearest" });
  }

  // ── 抓新聞 ─────────────────────────────────────────────────────
  function fetchNews(symbol: string): void {
    fetch(`/momentum/news?symbol=${encodeURIComponent(symbol)}`)
      .then((r) => r.json())
      .then((data: unknown) => {
        loaded[symbol] = true;
        renderNews(symbol, parseNews(data));
      })
      .catch(() => { renderErr(symbol); });
  }

  // ── 渲染 ───────────────────────────────────────────────────────
  function renderNews(symbol: string, news: NewsItem[]): void {
    const panel = document.getElementById(`npanel-${symbol}`);
    if (!panel) return;
    if (!news.length) {
      panel.innerHTML = '<p class="py-8 text-center text-gray-400 text-sm">目前無相關新聞</p>';
      return;
    }
    panel.innerHTML = news.map((n) => {
      let bodyHtml = "";
      if (n.content_html && n.content_html.trim()) {
        bodyHtml = '<div class="md-body text-sm text-gray-700 leading-relaxed mb-2 overflow-x-auto">'
          + n.content_html
          + "</div>";
      }
      return (
        '<div class="py-4">'
          + `<p class="text-sm font-semibold text-gray-900 leading-snug mb-2">${esc(n.headline)}</p>`
          + bodyHtml
          + '<div class="flex flex-wrap items-center gap-x-3 gap-y-1 text-xs text-gray-400 mt-2">'
            + (n.datetime ? `<span>${esc(n.datetime)}</span>` : "")
            + (n.source ? `<span class="font-medium">${esc(n.source)}</span>` : "")
            + (n.url
              ? `<a href="${esc(n.url)}" target="_blank" rel="noopener noreferrer" `
                + `class="text-blue-500 hover:underline truncate max-w-xs">${esc(n.source || n.url)} ↗</a>`
              : "")
          + "</div>"
        + "</div>"
      );
    }).join("");
  }

  function renderErr(symbol: string): void {
    const panel = document.getElementById(`npanel-${symbol}`);
    if (panel) {
      panel.innerHTML = '<p class="py-8 text-center text-red-400 text-sm">新聞載入失敗，請稍後再試</p>';
    }
  }

  function esc(s: string): string {
    return String(s)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;");
  }
}
