/**
 * LEAPS 頁 IV 環境區塊的兩張圖（leaps-iv-environment P5）。
 *
 * - Barchart IV Rank 走勢：IV Rank（左軸）＋股價（右軸）雙軸折線
 * - ATM IV 期限結構：x＝DTE、y＝ATM IV%，虛線標 540 天
 *
 * 資料由 Phlex 元件放在 canvas 的 data-ivenv-points（JSON）。區塊預設收合，收合中的
 * canvas 量不到尺寸，所以第一次展開時才畫；之後重複展開不重畫。
 * 寫法沿用 P0 第 7 點記錄的既有 Chart.js 用法：layout 以 CDN 載入、實例重繪前 destroy。
 */

import { arr, numeric } from "./shared/json";

const TARGET_DTE = 540;

export interface TermPoint {
  x: number;
  y: number;
}

export interface BarchartSeries {
  labels: string[];
  rank: (number | null)[];
  price: (number | null)[];
}

function parseJson(raw: string | undefined): unknown {
  if (!raw) return undefined;
  try {
    return JSON.parse(raw);
  } catch {
    return undefined;
  }
}

/** 期限結構點：只收 x、y 都是數字的點（nil 的到期日伺服器端已排除，這裡再擋一次）。 */
export function parseTermPoints(raw: string | undefined): TermPoint[] {
  const data = parseJson(raw);
  if (!Array.isArray(data)) return [];
  return data.flatMap((p) => {
    const x = numeric(p, "x");
    const y = numeric(p, "y");
    return x === undefined || y === undefined ? [] : [{ x, y }];
  });
}

export function parseBarchartSeries(raw: string | undefined): BarchartSeries {
  const data = parseJson(raw);
  const nums = (key: string): (number | null)[] =>
    arr(data, key).map((v) => (typeof v === "number" && !isNaN(v) ? v : null));
  return {
    labels: arr(data, "labels").map((v) => (typeof v === "string" ? v : "")),
    rank: nums("rank"),
    price: nums("price"),
  };
}

/** 540 天虛線的兩個端點：跨整個 y 範圍（含一點留白）。 */
export function targetLine(points: TermPoint[]): TermPoint[] {
  if (points.length === 0) return [];
  const ys = points.map((p) => p.y);
  const pad = 1;
  return [
    { x: TARGET_DTE, y: Math.min(...ys) - pad },
    { x: TARGET_DTE, y: Math.max(...ys) + pad },
  ];
}

const charts = new Map<HTMLCanvasElement, ChartInstance>();

function draw(canvas: HTMLCanvasElement, config: unknown): void {
  if (typeof Chart === "undefined") return;
  charts.get(canvas)?.destroy();
  charts.set(canvas, new Chart(canvas, config));
}

function drawBarchart(canvas: HTMLCanvasElement): void {
  const s = parseBarchartSeries(canvas.dataset["ivenvPoints"]);
  if (s.labels.length === 0) return;
  draw(canvas, {
    type: "line",
    data: {
      labels: s.labels,
      datasets: [
        {
          label: "Barchart IV Rank",
          data: s.rank,
          borderColor: "#2563eb",
          borderWidth: 1.5,
          pointRadius: 0,
          tension: 0.2,
          yAxisID: "y",
        },
        {
          label: "股價",
          data: s.price,
          borderColor: "#d97706",
          borderWidth: 1.2,
          borderDash: [4, 3],
          pointRadius: 0,
          tension: 0.2,
          yAxisID: "y2",
        },
      ],
    },
    options: {
      responsive: true,
      maintainAspectRatio: false,
      interaction: { mode: "index", intersect: false },
      plugins: { legend: { labels: { font: { size: 11 } } } },
      scales: {
        x: { ticks: { maxTicksLimit: 8, maxRotation: 0, font: { size: 10 } } },
        y: {
          position: "left",
          min: 0,
          max: 100,
          title: { display: true, text: "IV Rank" },
        },
        y2: {
          position: "right",
          grid: { drawOnChartArea: false },
          title: { display: true, text: "股價" },
        },
      },
    },
  });
}

function drawTerm(canvas: HTMLCanvasElement): void {
  const points = parseTermPoints(canvas.dataset["ivenvPoints"]);
  if (points.length === 0) return;
  draw(canvas, {
    type: "line",
    data: {
      datasets: [
        {
          label: "ATM IV %",
          data: points,
          borderColor: "#2563eb",
          backgroundColor: "#2563eb",
          borderWidth: 2,
          pointRadius: 3,
          tension: 0,
        },
        {
          label: "540 天",
          data: targetLine(points),
          borderColor: "#9ca3af",
          borderWidth: 1,
          borderDash: [5, 4],
          pointRadius: 0,
        },
      ],
    },
    options: {
      responsive: true,
      maintainAspectRatio: false,
      parsing: false,
      plugins: { legend: { labels: { font: { size: 11 } } } },
      scales: {
        x: { type: "linear", title: { display: true, text: "DTE（天）" } },
        y: { title: { display: true, text: "ATM IV %" } },
      },
    },
  });
}

function drawAll(root: HTMLElement): void {
  root
    .querySelectorAll<HTMLCanvasElement>("canvas[data-ivenv-chart]")
    .forEach((canvas) => {
      if (canvas.dataset["ivenvChart"] === "barchart") drawBarchart(canvas);
      else if (canvas.dataset["ivenvChart"] === "term") drawTerm(canvas);
    });
}

export function init(root: HTMLElement): void {
  if (!(root instanceof HTMLDetailsElement)) return;
  let drawn = false;
  const onToggle = (): void => {
    if (!root.open || drawn) return;
    drawn = true;
    drawAll(root);
  };
  root.addEventListener("toggle", onToggle);
  onToggle(); // 伺服器端若已展開（目前預設收合，保險起見）
}
