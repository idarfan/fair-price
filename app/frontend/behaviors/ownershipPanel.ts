/**
 * 持股結構面板：點擊代號後載入機構/內部人持股。
 *
 * 稽核 H-3：原本內嵌在 app/components/shared/ownership_panel_component.rb 的 heredoc 裡。
 */

import { closestFrom } from "./shared/dom";
import { arr, isRecord, num, str } from "./shared/json";

interface Summary {
  institutions_pct?: number;
  insiders_pct?: number;
  institutions_float_pct?: number;
  institutions_count?: number;
}

interface Holder {
  name: string;
  pct_held?: number;
  value?: number;
  report_date?: string;
}

interface OwnershipData {
  error?: string;
  source?: string;
  summary?: Summary;
  top_holders: Holder[];
}

function parseOwnership(payload: unknown): OwnershipData {
  const out: OwnershipData = { top_holders: [] };
  if (!isRecord(payload)) return out;

  const err = str(payload, "error");
  if (err !== undefined) out.error = err;
  const source = str(payload, "source");
  if (source !== undefined) out.source = source;

  const rawSummary = payload["summary"];
  if (isRecord(rawSummary)) {
    const s: Summary = {};
    const ip = num(rawSummary, "institutions_pct");
    if (ip !== undefined) s.institutions_pct = ip;
    const inp = num(rawSummary, "insiders_pct");
    if (inp !== undefined) s.insiders_pct = inp;
    const ifp = num(rawSummary, "institutions_float_pct");
    if (ifp !== undefined) s.institutions_float_pct = ifp;
    const ic = num(rawSummary, "institutions_count");
    if (ic !== undefined) s.institutions_count = ic;
    out.summary = s;
  }

  out.top_holders = arr(payload, "top_holders").flatMap((raw): Holder[] => {
    if (!isRecord(raw)) return [];
    const name = str(raw, "name");
    if (name === undefined) return [];
    const h: Holder = { name };
    const pct = num(raw, "pct_held");
    if (pct !== undefined) h.pct_held = pct;
    const value = num(raw, "value");
    if (value !== undefined) h.value = value;
    const rd = str(raw, "report_date");
    if (rd !== undefined) h.report_date = rd;
    return [h];
  });

  return out;
}

const SHORT_TOOLTIP = "持股比例超過 100%，通常因放空借券導致同一股票被重複計入，屬正常市場現象";

function fmtPct(val: number | null | undefined): string {
  if (val == null) return "—";
  const pct = val * 100;
  let s = `${pct.toFixed(2)}%`;
  if (pct > 100) s += ` <span title="${SHORT_TOOLTIP}" class="cursor-help">⚠️</span>`;
  return s;
}

function fmtBillion(val: number | null | undefined): string {
  if (val == null) return "—";
  if (val >= 1e9) return `$${(val / 1e9).toFixed(2)}B`;
  if (val >= 1e6) return `$${(val / 1e6).toFixed(2)}M`;
  return `$${val.toLocaleString("en-US")}`;
}

export function init(): void {
  // 型別化前這些元素一律直接取用，缺任何一個都會在掛載當下就拋錯。
  // 面板是同一段標記一起渲染的，缺一即代表整個面板不存在，直接不掛載。
  const panelEl = document.getElementById("ownership-panel");
  const titlebarEl = document.getElementById("ownership-titlebar");
  const loadingEl = document.getElementById("ownership-loading");
  const errEl = document.getElementById("ownership-error");
  const contentEl = document.getElementById("ownership-body");
  const headingEl = document.getElementById("ownership-title");
  const imgEl = document.getElementById("ownership-logo-img");
  if (!panelEl || !titlebarEl || !loadingEl || !errEl || !contentEl || !headingEl) return;
  if (!(imgEl instanceof HTMLImageElement)) return;

  // 明確型別的 const：narrowing 在巢狀 function declaration 裡不保證留存，
  // 用這種寫法就不需要在每個使用點寫非空斷言。
  const panel: HTMLElement = panelEl;
  const titlebar: HTMLElement = titlebarEl;
  const loading: HTMLElement = loadingEl;
  const errorEl: HTMLElement = errEl;
  const bodyEl: HTMLElement = contentEl;
  const titleEl: HTMLElement = headingEl;
  const logoImg: HTMLImageElement = imgEl;

  // ── 拖曳 ───────────────────────────────────────────────────────
  let isDragging = false;
  let dragOffX = 0;
  let dragOffY = 0;

  titlebar.addEventListener("mousedown", (e) => {
    const target = e.target;
    if (target instanceof Element && target.id === "ownership-close-btn") return;
    isDragging = true;
    const rect = panel.getBoundingClientRect();
    panel.style.transform = "none";
    panel.style.top = `${rect.top}px`;
    panel.style.left = `${rect.left}px`;
    panel.style.right = "auto";
    dragOffX = e.clientX - rect.left;
    dragOffY = e.clientY - rect.top;
    e.preventDefault();
  });
  document.addEventListener("mousemove", (e) => {
    if (!isDragging) return;
    panel.style.left = `${e.clientX - dragOffX}px`;
    panel.style.top = `${e.clientY - dragOffY}px`;
  });
  document.addEventListener("mouseup", () => { isDragging = false; });

  // ── 開 / 關 ────────────────────────────────────────────────────
  function openOwnershipPanel(symbol: string): void {
    panel.style.left = "50%";
    panel.style.right = "auto";
    panel.style.top = "50%";
    panel.style.transform = "translate(-50%, -50%)";

    titleEl.textContent = `${symbol} 持股結構`;
    logoImg.src = `https://assets.parqet.com/logos/symbol/${symbol}?format=jpg`;
    logoImg.alt = symbol;
    // 元件端改用 hidden class 表示初始隱藏（CSP style-src 收斂），
    // 這裡跟著切 class——和 inline style 混用會讓層疊關係難判讀。
    loading.classList.remove("hidden");
    errorEl.classList.add("hidden");
    bodyEl.classList.add("hidden");
    panel.classList.remove("hidden");

    fetch(`/portfolio/ownership?symbol=${encodeURIComponent(symbol)}`)
      .then((r) => r.json())
      .then((raw: unknown) => {
        const data = parseOwnership(raw);
        loading.classList.add("hidden");
        if (data.error || (!data.summary && data.top_holders.length === 0)) {
          errorEl.textContent = "無法取得持股資料，請稍後再試";
          errorEl.classList.remove("hidden");
          return;
        }
        renderOwnershipData(data, symbol);
        bodyEl.classList.remove("hidden");
      })
      .catch(() => {
        loading.classList.add("hidden");
        errorEl.textContent = "載入失敗，請檢查網路連線";
        errorEl.classList.remove("hidden");
      });
  }

  function closeOwnershipPanel(): void {
    panel.classList.add("hidden");
  }

  // ── 渲染 ───────────────────────────────────────────────────────
  function renderOwnershipData(data: OwnershipData, symbol: string): void {
    const sourceLabel = data.source ? ` · 來源：${data.source}` : "";
    titleEl.textContent = `${symbol} 持股結構${sourceLabel}`;

    const summaryEl = document.getElementById("ownership-summary");
    if (summaryEl) {
      summaryEl.innerHTML = "";
      const s = data.summary;
      const cards: { label: string; val?: number | undefined; raw?: string }[] = s ? [
        { label: "機構持股（佔總股本）", val: s.institutions_pct },
        { label: "內部人持股（佔總股本）", val: s.insiders_pct },
        { label: "機構持有 Float（佔流通股）", val: s.institutions_float_pct },
        { label: "機構總數",
          raw: s.institutions_count != null ? s.institutions_count.toLocaleString() : "—" },
      ] : [];
      cards.forEach((c) => {
        const display = c.raw !== undefined ? c.raw : fmtPct(c.val);
        const d = document.createElement("div");
        d.className = "bg-gray-50 rounded-lg px-3 py-2";
        d.innerHTML = `<p class="text-xs text-gray-400 mb-0.5">${c.label}</p>`
          + `<p class="text-sm font-bold text-gray-800">${display}</p>`;
        summaryEl.appendChild(d);
      });
    }

    const holdersBody = document.getElementById("ownership-holders-body");
    if (!holdersBody) return;
    holdersBody.innerHTML = "";
    if (data.top_holders.length === 0) {
      const tr = document.createElement("tr");
      tr.innerHTML = '<td colspan="4" class="px-2 py-4 text-center text-gray-300">無資料</td>';
      holdersBody.appendChild(tr);
      return;
    }
    data.top_holders.forEach((h) => {
      const tr = document.createElement("tr");
      tr.className = "border-t border-gray-50";
      tr.innerHTML =
        `<td class="px-2 py-1.5 text-gray-700 max-w-xs truncate" title="${h.name}">${h.name}</td>`
        + `<td class="px-2 py-1.5 text-right font-mono text-gray-700">${fmtPct(h.pct_held)}</td>`
        + `<td class="px-2 py-1.5 text-right text-gray-500">${fmtBillion(h.value)}</td>`
        + `<td class="px-2 py-1.5 text-right text-gray-400">${h.report_date || "—"}</td>`;
      holdersBody.appendChild(tr);
    });
  }

  // ── 事件綁定 ───────────────────────────────────────────────────
  document.addEventListener("click", (e) => {
    const cell = closestFrom(e, "[data-ownership-symbol]");
    if (!cell) return;
    const symbol = cell.dataset["ownershipSymbol"];
    if (symbol) openOwnershipPanel(symbol);
  });

  document.getElementById("ownership-close-btn")
    ?.addEventListener("click", closeOwnershipPanel);
  document.addEventListener("keydown", (e) => {
    if (e.key === "Escape") closeOwnershipPanel();
  });
}
