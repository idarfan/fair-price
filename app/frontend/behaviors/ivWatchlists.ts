/**
 * IV Skew 追蹤清單：圖表載入、切換啟用、移除。
 *
 * 稽核 H-3：原本內嵌在 app/components/iv_watchlists/index_view.rb 的 heredoc 裡。
 * Chart.js 由 layout 以獨立 <script> 從 CDN 載入（型別見 types/globals.d.ts）。
 */

import { closestFrom, csrfToken } from "./shared/dom";
import { arr, isRecord, num, str } from "./shared/json";

interface ChartPayload {
  error?: string;
  intraday: boolean;
  labels: unknown[];
  put_iv: unknown[];
  call_iv: unknown[];
  price: unknown[];
  skew: number[];
  p75: number;
}

function parsePayload(raw: unknown): ChartPayload {
  const skew = arr(raw, "skew").map((v) => typeof v === "number" ? v : NaN);
  const payload: ChartPayload = {
    intraday: isRecord(raw) && raw["intraday"] === true,
    labels: arr(raw, "labels"),
    put_iv: arr(raw, "put_iv"),
    call_iv: arr(raw, "call_iv"),
    price: arr(raw, "price"),
    skew,
    p75: num(raw, "p75") ?? Infinity,
  };
  const err = str(raw, "error");
  if (err !== undefined) payload.error = err;
  return payload;
}

interface AfterEventArgs {
  event: { type: string };
}

export function init(): void {
  const ivCharts: Record<string, ChartInstance | undefined> = {};

  function makeCrosshair(rowId: string): unknown {
    return {
      id: "crosshair",
      afterEvent: (chart: ChartInstance, args: AfterEventArgs): void => {
        const e = args.event;
        const line = document.getElementById(`ch-line-${rowId}`);
        if (!line) return;
        const active = chart.tooltip?._active;
        if (e.type === "mousemove" && active && active.length) {
          const first = active[0];
          if (!first) return;
          const idx = first.index;
          const ivC = ivCharts[`${rowId}-iv`];
          if (!ivC) return;
          const meta = ivC.getDatasetMeta(0);
          const point = meta.data[idx];
          if (!point) return;
          const cRect = ivC.canvas.getBoundingClientRect();
          const parent = line.parentElement;
          if (!parent) return;
          const wRect = parent.getBoundingClientRect();
          line.style.left = `${point.x + cRect.left - wRect.left}px`;
          line.style.display = "block";
        } else if (e.type === "mouseout") {
          line.style.display = "none";
        }
      },
    };
  }

  async function loadIvChart(symbol: string, rowId: string, days: number): Promise<void> {
    const loadingEl = document.querySelector(`[data-iv-chart-target="loading-${rowId}"]`);
    loadingEl?.classList.remove("hidden");

    const ivKey = `${rowId}-iv`;
    const skewKey = `${rowId}-skew`;
    ivCharts[ivKey]?.destroy();
    delete ivCharts[ivKey];
    ivCharts[skewKey]?.destroy();
    delete ivCharts[skewKey];

    const res = await fetch(`/iv_watchlists/chart_data/${symbol}?days=${days}`);
    const data = parsePayload(await res.json());

    loadingEl?.classList.add("hidden");

    if (data.error === "no_data") {
      const canvas = document.getElementById(`chart-iv-${rowId}`);
      if (!(canvas instanceof HTMLCanvasElement)) return;
      canvas.height = 80;
      const ctx = canvas.getContext("2d");
      if (!ctx) return;
      ctx.fillStyle = "#888";
      ctx.font = "13px sans-serif";
      ctx.textAlign = "center";
      ctx.fillText("尚無資料，請等待每日抓取累積", canvas.width / 2, 44);
      return;
    }

    interface TickScale {
      getLabelForValue(v: number): string;
    }
    const makeXTicks = (maxLabels: number, intraday: boolean): unknown => ({
      color: "#666", autoSkip: false,
      maxRotation: intraday ? 45 : 0, minRotation: 0,
      font: { size: 9 },
      callback: function (this: TickScale, value: number, index: number, ticks: unknown[]): string | null {
        const n = ticks.length;
        const step = Math.max(1, Math.floor(n / maxLabels));
        if (index === 0 || index === n - 1 || index % step === 0) return this.getLabelForValue(value);
        return null;
      },
    });
    const xAxisCfg = data.intraday
      ? { ticks: makeXTicks(14, true), grid: { color: "#1e1e1e" } }
      : { ticks: makeXTicks(8, false), grid: { color: "#1e1e1e" } };

    const ivCanvas = document.getElementById(`chart-iv-${rowId}`);
    if (ivCanvas instanceof HTMLCanvasElement && typeof Chart !== "undefined") {
      const ctx = ivCanvas.getContext("2d");
      if (ctx) {
        ivCharts[ivKey] = new Chart(ctx, {
          type: "line",
          data: {
            labels: data.labels,
            datasets: [
              { label: "Put IV %", data: data.put_iv, borderColor: "#E85D5D", borderWidth: 1.5, pointRadius: 0, tension: 0.3, yAxisID: "y" },
              { label: "Call IV %", data: data.call_iv, borderColor: "#2ECC9A", borderWidth: 1.5, pointRadius: 0, tension: 0.3, yAxisID: "y" },
              { label: "股價", data: data.price, borderColor: "#D4A017", borderWidth: 1.2, borderDash: [4, 3], pointRadius: 0, tension: 0.3, yAxisID: "y2" },
            ],
          },
          options: {
            responsive: true, maintainAspectRatio: false,
            interaction: { mode: "index", intersect: false },
            plugins: {
              legend: { labels: { color: "#aaa", font: { size: 10 } } },
              tooltip: { backgroundColor: "#1a1a1a", titleColor: "#ccc", bodyColor: "#aaa" },
            },
            scales: {
              x: xAxisCfg,
              y: { position: "left", ticks: { color: "#aaa", font: { size: 9 } }, grid: { color: "#1e1e1e" }, title: { display: true, text: "IV %", color: "#aaa", font: { size: 9 } } },
              y2: { position: "right", ticks: { color: "#D4A017", font: { size: 9 } }, grid: { drawOnChartArea: false }, title: { display: true, text: "Price", color: "#D4A017", font: { size: 9 } } },
            },
          },
          plugins: [makeCrosshair(rowId)],
        });
      }
    }

    // 讀取 IV 圖右軸實際寬度，作為 Skew 圖右側 padding，確保兩圖 chartArea 對齊
    const skewCanvas = document.getElementById(`chart-skew-${rowId}`);
    if (skewCanvas instanceof HTMLCanvasElement && typeof Chart !== "undefined") {
      const ctx = skewCanvas.getContext("2d");
      if (ctx) {
        const barColors = data.skew.map((v) =>
          v >= data.p75 ? "rgba(224,64,176,0.75)" : "rgba(85,119,170,0.75)");
        interface TooltipItem { raw: unknown }
        ivCharts[skewKey] = new Chart(ctx, {
          type: "bar",
          data: { labels: data.labels, datasets: [{ label: "Skew %", data: data.skew, backgroundColor: barColors, borderWidth: 0 }] },
          options: {
            responsive: true, maintainAspectRatio: false,
            plugins: {
              legend: { labels: { color: "#aaa", font: { size: 10 } } },
              tooltip: {
                backgroundColor: "#1a1a1a", titleColor: "#ccc", bodyColor: "#aaa",
                callbacks: {
                  afterBody: (items: TooltipItem[]): string[] => {
                    const first = items[0];
                    return first && typeof first.raw === "number" && first.raw >= data.p75
                      ? ["⚠️ 恐慌區（> 75th pct）"] : [];
                  },
                },
              },
            },
            scales: {
              x: xAxisCfg,
              y: { ticks: { color: "#aaa", font: { size: 9 } }, grid: { color: "#1e1e1e" }, title: { display: true, text: "Skew %", color: "#aaa", font: { size: 9 } } },
              y2: {
                position: "right",
                display: true,
                afterFit: (scale: { width: number }): void => {
                  const ivC = ivCharts[ivKey];
                  const y2 = ivC?.scales["y2"];
                  if (y2) scale.width = y2.width;
                },
                ticks: { display: false, maxTicksLimit: 0 },
                grid: { display: false },
                border: { display: false },
                title: { display: false },
              },
            },
          },
          plugins: [makeCrosshair(rowId)],
        });
      }
    }
  }

  document.addEventListener("click", (e) => {
    void (async (): Promise<void> => {
      const toggleBtn = closestFrom(e, '[data-action="click->watchlist#toggle:stop"]');
      if (toggleBtn) {
        e.stopPropagation();
        const url = toggleBtn.dataset["url"];
        if (!url) return;
        const res = await fetch(url, {
          method: "PATCH", headers: { "X-CSRF-Token": csrfToken(), "Accept": "application/json" },
        });
        const d: unknown = await res.json();
        if (!isRecord(d) || d["success"] !== true) return;
        const active = d["active"] === true;
        toggleBtn.classList.toggle("bg-green-600", active);
        toggleBtn.classList.toggle("bg-gray-600", !active);
        const dot = toggleBtn.querySelector("span");
        if (dot) {
          dot.classList.toggle("left-5", active);
          dot.classList.toggle("left-1", !active);
        }
        return;
      }

      const removeBtn = closestFrom(e, '[data-action="click->watchlist#remove:stop"]');
      if (removeBtn) {
        e.stopPropagation();
        const url = removeBtn.dataset["url"];
        if (!url) return;
        if (!confirm(`確定移除 ${removeBtn.dataset["symbol"] ?? ""}？`)) return;
        const res = await fetch(url, {
          method: "DELETE", headers: { "X-CSRF-Token": csrfToken(), "Accept": "application/json" },
        });
        const d: unknown = await res.json();
        if (isRecord(d) && d["success"] === true) {
          document.getElementById(`watchlist-row-${removeBtn.dataset["id"]}`)?.remove();
        }
        return;
      }

      const chartRow = closestFrom(e, '[data-action="click->iv-chart#toggle"]');
      if (chartRow) {
        const symbol = chartRow.dataset["symbol"];
        const rowId = chartRow.dataset["rowId"];
        if (!symbol || !rowId) return;
        const panel = document.getElementById(`chart-panel-${rowId}`);
        const arrow = document.querySelector(`[data-iv-chart-target="arrow-${rowId}"]`);
        if (!panel) return;
        const isOpen = !panel.classList.contains("hidden");
        if (isOpen) {
          panel.classList.add("hidden");
          if (arrow instanceof HTMLElement) arrow.style.transform = "";
        } else {
          panel.classList.remove("hidden");
          if (arrow instanceof HTMLElement) arrow.style.transform = "rotate(90deg)";
          await loadIvChart(symbol, rowId, 90);
        }
        return;
      }

      const dayBtn = closestFrom(e, '[data-action="click->iv-chart#changeDays"]');
      if (dayBtn) {
        const symbol = dayBtn.dataset["symbol"];
        const rowId = dayBtn.dataset["rowId"];
        if (!symbol || !rowId) return;
        const panel = document.getElementById(`chart-panel-${rowId}`);
        if (!panel) return;
        panel.querySelectorAll('[data-action="click->iv-chart#changeDays"]').forEach((btn) => {
          btn.classList.remove("bg-blue-600", "border-blue-500", "text-white");
          btn.classList.add("bg-gray-800", "border-gray-600", "text-gray-400");
        });
        dayBtn.classList.add("bg-blue-600", "border-blue-500", "text-white");
        dayBtn.classList.remove("bg-gray-800", "border-gray-600", "text-gray-400");
        await loadIvChart(symbol, rowId, parseInt(dayBtn.dataset["days"] ?? "", 10));
        return;
      }

      const chip = closestFrom(e, '[data-action="click->watchlist-form#quickAdd"]');
      if (chip) {
        const input = document.querySelector('[data-watchlist-form-target="input"]');
        if (input instanceof HTMLInputElement) {
          input.value = chip.dataset["symbol"] ?? "";
          input.focus();
        }
      }
    })();
  });
}
