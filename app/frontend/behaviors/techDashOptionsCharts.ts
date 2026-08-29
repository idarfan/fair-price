/**
 * 技術面儀表板：期權相關圖表（Max Pain、OI、Skew、各到期日 Max Pain）。
 *
 * 需要的資料由掛載元素的 data attribute 傳入：root.dataset.symbol
 * 各圖的資料放在頁面上的 <script type="application/json"> 資料島（mp-d1..d4）。
 *
 * 稽核 H-3 Wave 2：原本內嵌在 app/components/technical_dashboard/page_component.rb 的 heredoc 裡。
 * Chart.js 由 layout 以獨立 <script> 從 CDN 載入（型別見 types/globals.d.ts）。
 *
 * 型別化時把四段逐字重複的 tooltip 容器建立邏輯抽成 makeTipBox()——只差 id 與
 * min-width 兩個參數，否則同一組型別註記要重複四次。行為不變。
 */

import { arr, isRecord, num } from "./shared/json";

// ── 這個檔案實際會碰到的 Chart.js 形狀（不追求完整覆蓋官方型別）──────────
interface VLine {
  value: number;
  color?: string;
  dash?: number[];
  label?: string;
}

interface ChartScale {
  left: number;
  right: number;
  top: number;
  bottom: number;
  getLabels?: () => string[];
  getPixelForValue: (v: number) => number;
}

interface ChartLike {
  ctx: CanvasRenderingContext2D;
  scales: { x: ChartScale; y: ChartScale };
  options: { vlines?: VLine[] };
}

interface TooltipDataPoint {
  dataset: { label: string };
  raw: unknown;
}

interface TooltipModel {
  opacity: number;
  title?: string[];
  dataPoints?: TooltipDataPoint[];
}

interface TooltipContext {
  tooltip: TooltipModel;
}

// ── 資料島 ──────────────────────────────────────────────────────────────
interface ByExpiryRow {
  expiry: string;
  max_pain_strike: number;
}

interface ChartData {
  strikes: unknown[];
  call_pain: unknown[];
  put_pain: unknown[];
  call_oi: unknown[];
  put_oi: unknown[];
  iv_combined: unknown[];
  max_pain_strike: number | undefined;
  last_price: number | undefined;
  volume_oi_filter: string | undefined;
  by_expiry: ByExpiryRow[];
}

function readData(id: string): ChartData | null {
  const el = document.getElementById(id);
  if (!el || !el.textContent) return null;
  let parsed: unknown;
  try { parsed = JSON.parse(el.textContent); } catch { return null; }
  if (!isRecord(parsed)) return null;

  const filter = parsed["volume_oi_filter"];
  return {
    strikes: arr(parsed, "strikes"),
    call_pain: arr(parsed, "call_pain"),
    put_pain: arr(parsed, "put_pain"),
    call_oi: arr(parsed, "call_oi"),
    put_oi: arr(parsed, "put_oi"),
    iv_combined: arr(parsed, "iv_combined"),
    max_pain_strike: num(parsed, "max_pain_strike"),
    last_price: num(parsed, "last_price"),
    volume_oi_filter: typeof filter === "string" ? filter : undefined,
    by_expiry: arr(parsed, "by_expiry").flatMap((row): ByExpiryRow[] => {
      if (!isRecord(row)) return [];
      const expiry = row["expiry"];
      const strike = num(row, "max_pain_strike");
      if (typeof expiry !== "string" || strike === undefined) return [];
      return [{ expiry, max_pain_strike: strike }];
    }),
  };
}

const GRID = "#e5e7eb";
const TICK = { color: "#6b7280", font: { size: 10 } };
const LEGEND = {
  position: "top",
  labels: { color: "#6b7280", font: { size: 11 }, boxWidth: 12 },
};

const TIP_BASE = "position:absolute;top:8px;right:8px;background:rgba(255,255,255,0.97);"
  + "border:1px solid #d1d5db;border-radius:4px;padding:7px 11px;font-size:11px;"
  + "line-height:1.7;z-index:10;pointer-events:none;box-shadow:0 2px 6px rgba(0,0,0,0.13);";

function makeTipBox(canvas: HTMLElement, tipId: string, minWidth: string): HTMLElement | null {
  const existing = document.getElementById(tipId);
  if (existing) return existing;
  const parent = canvas.parentElement;
  if (!parent) return null;
  const tipEl = document.createElement("div");
  tipEl.id = tipId;
  tipEl.style.cssText = `${TIP_BASE}min-width:${minWidth};`;
  parent.appendChild(tipEl);
  return tipEl;
}

/** 讀 dataPoints 裡標籤含指定字串的那一筆的原始值。 */
function rawWhereLabel(tip: TooltipModel, needle: string): number | null {
  let found: number | null = null;
  (tip.dataPoints ?? []).forEach((dp) => {
    if (dp.dataset.label.indexOf(needle) >= 0 && typeof dp.raw === "number") found = dp.raw;
  });
  return found;
}

function titleOf(tip: TooltipModel): string {
  return tip.title?.[0] ?? "";
}

export function init(root: HTMLElement): void {
  const sym = root.dataset["symbol"];
  if (!sym) return;
  if (typeof Chart === "undefined") return;

  // 垂直參考線 plugin——category 軸要用 label index，不能直接用數值
  const vlinePlugin = {
    id: `mp_vline_${sym}`,
    afterDraw: (chart: ChartLike): void => {
      const lines = chart.options.vlines;
      if (!lines || !lines.length) return;
      const ctx = chart.ctx;
      const xAxis = chart.scales.x;
      const yAxis = chart.scales.y;
      const labels = xAxis.getLabels ? xAxis.getLabels() : [];
      lines.forEach((vl) => {
        let xPx: number;
        if (labels.length > 0) {
          let nearestIdx = 0;
          let minDiff = Infinity;
          labels.forEach((lbl, idx) => {
            const diff = Math.abs(parseFloat(lbl) - vl.value);
            if (diff < minDiff) { minDiff = diff; nearestIdx = idx; }
          });
          xPx = xAxis.getPixelForValue(nearestIdx);
        } else {
          xPx = xAxis.getPixelForValue(vl.value);
        }
        if (!xPx || xPx < xAxis.left || xPx > xAxis.right) return;
        ctx.save();
        ctx.beginPath();
        ctx.setLineDash(vl.dash ?? []);
        ctx.strokeStyle = vl.color ?? "rgba(0,0,0,0.4)";
        ctx.lineWidth = 1.5;
        ctx.moveTo(xPx, yAxis.top);
        ctx.lineTo(xPx, yAxis.bottom);
        ctx.stroke();
        if (vl.label) {
          ctx.fillStyle = vl.color ?? "rgba(0,0,0,0.5)";
          ctx.font = "10px sans-serif";
          ctx.fillText(vl.label, xPx + 3, yAxis.top + 12);
        }
        ctx.restore();
      });
    },
  };

  // ── 圖 1：Max Pain ────────────────────────────────────────────────
  (() => {
    const d = readData(`mp-d1-${sym}`);
    const cv = document.getElementById(`mp-c1-${sym}`);
    if (!d || !(cv instanceof HTMLCanvasElement)) return;

    const vlines: VLine[] = [];
    if (d.max_pain_strike !== undefined) {
      vlines.push({
        value: d.max_pain_strike, color: "rgba(37,99,235,0.8)", dash: [5, 3],
        label: `Max Pain $${d.max_pain_strike}`,
      });
    }
    if (d.last_price !== undefined) {
      vlines.push({
        value: d.last_price, color: "rgba(107,114,128,0.6)", dash: [4, 3],
        label: `Last $${d.last_price.toFixed(2)}`,
      });
    }

    new Chart(cv, {
      type: "bar",
      plugins: [vlinePlugin],
      data: {
        labels: d.strikes,
        datasets: [
          { label: "Calls - Max Pain", data: d.call_pain,
            backgroundColor: "rgba(34,197,94,0.65)", borderColor: "rgba(22,163,74,0.8)",
            borderWidth: 1, borderRadius: 2 },
          { label: "Puts - Max Pain", data: d.put_pain,
            backgroundColor: "rgba(239,68,68,0.65)", borderColor: "rgba(220,38,38,0.8)",
            borderWidth: 1, borderRadius: 2 },
        ],
      },
      options: {
        responsive: true, maintainAspectRatio: false, animation: false,
        plugins: {
          legend: LEGEND,
          tooltip: {
            enabled: false, mode: "index", intersect: false,
            external: (context: TooltipContext): void => {
              const tipEl = makeTipBox(cv, `mp-tip-${sym}`, "140px");
              if (!tipEl) return;
              const tip = context.tooltip;
              if (tip.opacity === 0) { tipEl.style.opacity = "0"; return; }
              tipEl.style.opacity = "1";
              const callVal = rawWhereLabel(tip, "Call");
              const putVal = rawWhereLabel(tip, "Put");
              const fmt = (v: number | null): string =>
                v != null ? `$${Number(v).toLocaleString("en-US", { minimumFractionDigits: 2 })}` : "N/A";
              tipEl.innerHTML =
                `<div style="font-weight:600;margin-bottom:2px;color:#111;">Strike: ${titleOf(tip)}</div>`
                + `<div style="color:#16a34a;">Call: ${fmt(callVal)}</div>`
                + `<div style="color:#dc2626;">Put: ${fmt(putVal)}</div>`
                + (d.max_pain_strike !== undefined
                  ? `<div style="margin-top:4px;color:#2563eb;font-size:10px;">Max Pain: $${d.max_pain_strike}</div>`
                  : "");
            },
          },
        },
        vlines,
        scales: {
          x: { ticks: { ...TICK, maxRotation: 45 }, grid: { color: GRID } },
          y: {
            ticks: { ...TICK, callback: (v: number): string | number => v >= 1000 ? `${(v / 1000).toFixed(0)}k` : v },
            grid: { color: GRID },
          },
        },
      },
    });
  })();

  // ── 圖 2：各履約價未平倉／成交量 ──────────────────────────────────
  (() => {
    const d = readData(`mp-d2-${sym}`);
    const cv = document.getElementById(`mp-c2-${sym}`);
    if (!d || !(cv instanceof HTMLCanvasElement)) return;
    const isVolume = d.volume_oi_filter === "volume";

    new Chart(cv, {
      type: "bar",
      plugins: [vlinePlugin],
      data: {
        labels: d.strikes,
        datasets: [
          { label: isVolume ? "Call Vol" : "Call OI", data: d.call_oi,
            backgroundColor: "rgba(59,130,246,0.65)", borderColor: "rgba(37,99,235,0.8)",
            borderWidth: 1, borderRadius: 2 },
          { label: isVolume ? "Put Vol" : "Put OI", data: d.put_oi,
            backgroundColor: "rgba(249,115,22,0.65)", borderColor: "rgba(234,88,12,0.8)",
            borderWidth: 1, borderRadius: 2 },
        ],
      },
      options: {
        responsive: true, maintainAspectRatio: false, animation: false,
        plugins: {
          legend: LEGEND,
          tooltip: {
            enabled: false, mode: "index", intersect: false,
            external: (context: TooltipContext): void => {
              const tipEl = makeTipBox(cv, `mp-tip2-${sym}`, "130px");
              if (!tipEl) return;
              const tip = context.tooltip;
              if (tip.opacity === 0) { tipEl.style.opacity = "0"; return; }
              tipEl.style.opacity = "1";
              const callOI = rawWhereLabel(tip, "Call");
              const putOI = rawWhereLabel(tip, "Put");
              const fmt = (v: number | null): string =>
                v != null ? Number(Math.abs(v)).toLocaleString("en-US") : "N/A";
              tipEl.innerHTML =
                `<div style="font-weight:600;margin-bottom:2px;color:#111;">Strike: ${titleOf(tip)}</div>`
                + `<div style="color:#2563eb;">${isVolume ? "Call Vol: " : "Call OI: "}${fmt(callOI)}</div>`
                + `<div style="color:#ea580c;">${isVolume ? "Put Vol: " : "Put OI: "}${fmt(putOI)}</div>`;
            },
          },
        },
        vlines: d.last_price !== undefined
          ? [{ value: d.last_price, color: "rgba(107,114,128,0.6)", dash: [4, 3], label: `Last $${d.last_price.toFixed(2)}` }]
          : [],
        scales: {
          x: { ticks: { ...TICK, maxRotation: 45 }, grid: { color: GRID } },
          y: {
            title: { display: true, text: isVolume ? "Volume" : "Open Interest", color: "#9ca3af", font: { size: 11 } },
            ticks: TICK, grid: { color: GRID },
          },
        },
      },
    });
  })();

  // ── 圖 3：波動率偏斜 ──────────────────────────────────────────────
  (() => {
    const d = readData(`mp-d3-${sym}`);
    const cv = document.getElementById(`mp-c3-${sym}`);
    if (!d || !(cv instanceof HTMLCanvasElement)) return;

    new Chart(cv, {
      type: "line",
      plugins: [vlinePlugin],
      data: {
        labels: d.strikes,
        datasets: [
          { label: "Call & Put IV (%)", data: d.iv_combined,
            borderColor: "rgba(234,179,8,0.9)", backgroundColor: "rgba(234,179,8,0.08)",
            borderWidth: 2, pointRadius: 2.5, pointBackgroundColor: "rgba(234,179,8,0.9)",
            fill: true, tension: 0.3 },
        ],
      },
      options: {
        responsive: true, maintainAspectRatio: false, animation: false,
        plugins: {
          legend: LEGEND,
          tooltip: {
            enabled: false, mode: "index", intersect: false,
            external: (context: TooltipContext): void => {
              const tipEl = makeTipBox(cv, `mp-tip3-${sym}`, "120px");
              if (!tipEl) return;
              const tip = context.tooltip;
              if (tip.opacity === 0) { tipEl.style.opacity = "0"; return; }
              tipEl.style.opacity = "1";
              let iv: number | null = null;
              (tip.dataPoints ?? []).forEach((dp) => {
                if (typeof dp.raw === "number") iv = dp.raw;
              });
              const ivText = iv !== null ? `${(iv as number).toFixed(2)}%` : "N/A";
              tipEl.innerHTML =
                `<div style="font-weight:600;margin-bottom:2px;color:#111;">Strike: ${titleOf(tip)}</div>`
                + `<div style="color:#ca8a04;">IV: ${ivText}</div>`
                + (d.last_price !== undefined
                  ? `<div style="margin-top:4px;color:#6b7280;font-size:10px;">Last: $${d.last_price.toFixed(2)}</div>`
                  : "");
            },
          },
        },
        vlines: d.last_price !== undefined
          ? [{ value: d.last_price, color: "rgba(107,114,128,0.6)", dash: [4, 3], label: `Last $${d.last_price.toFixed(2)}` }]
          : [],
        scales: {
          x: { ticks: { ...TICK, maxRotation: 45 }, grid: { color: GRID } },
          y: { ticks: { ...TICK, callback: (v: number): string => `${v.toFixed(1)}%` }, grid: { color: GRID } },
        },
      },
    });
  })();

  // ── 圖 4：各到期日的 Max Pain ─────────────────────────────────────
  (() => {
    const d = readData(`mp-d4-${sym}`);
    const cv = document.getElementById(`mp-c4-${sym}`);
    if (!d || !(cv instanceof HTMLCanvasElement)) return;
    if (!d.by_expiry.length) return;

    const labels = d.by_expiry.map((r) => r.expiry);
    const values = d.by_expiry.map((r) => r.max_pain_strike);
    const lastPrice = d.last_price;
    const lpLine = lastPrice !== undefined ? values.map(() => lastPrice) : [];

    const datasets: unknown[] = [
      { label: "Max Pain by Expiry", data: values,
        borderColor: "rgba(59,130,246,0.9)", backgroundColor: "rgba(59,130,246,0.1)",
        borderWidth: 2, pointRadius: 4, pointBackgroundColor: "rgba(59,130,246,0.9)",
        fill: false, tension: 0 },
    ];
    if (lastPrice !== undefined) {
      datasets.push({
        label: `Last Price $${lastPrice.toFixed(2)}`, data: lpLine,
        borderColor: "rgba(236,72,153,0.7)", borderDash: [5, 3],
        borderWidth: 1.5, pointRadius: 0, fill: false,
      });
    }

    new Chart(cv, {
      type: "line",
      data: { labels, datasets },
      options: {
        responsive: true, maintainAspectRatio: false, animation: false,
        plugins: {
          legend: LEGEND,
          tooltip: {
            enabled: false, mode: "index", intersect: false,
            external: (context: TooltipContext): void => {
              const tipEl = makeTipBox(cv, `mp-tip4-${sym}`, "150px");
              if (!tipEl) return;
              const tip = context.tooltip;
              if (tip.opacity === 0) { tipEl.style.opacity = "0"; return; }
              tipEl.style.opacity = "1";
              const mpVal = rawWhereLabel(tip, "Max Pain");
              const lpVal = rawWhereLabel(tip, "Last");
              tipEl.innerHTML =
                `<div style="font-weight:600;margin-bottom:2px;color:#111;">${titleOf(tip)}</div>`
                + `<div style="color:#2563eb;">Max Pain: $${mpVal != null ? mpVal.toFixed(2) : "N/A"}</div>`
                + (lpVal != null ? `<div style="color:#db2777;">Last Price: $${lpVal.toFixed(2)}</div>` : "");
            },
          },
        },
        scales: {
          x: { ticks: { ...TICK, maxRotation: 45 }, grid: { color: GRID } },
          y: { ticks: { ...TICK, callback: (v: number): string => `$${v}` }, grid: { color: GRID } },
        },
      },
    });
  })();
}
