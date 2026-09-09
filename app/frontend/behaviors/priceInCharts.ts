/**
 * Price-In 反推工具：兩張圖的 Chart.js 渲染（規格 S5／S6）。
 *
 * Chart.js 4.4.1 與 chartjs-plugin-annotation 3.x 由 layout 以 CDN 載入（見 layout 註解）。
 *
 * 字級：主標 22/500、數值標籤 24/700、列標籤與軸刻度 20。Chart.js 預設是 12px，
 * 每一處都必須明確指定，漏一處那一處就縮回去。
 */

import { isRecord } from "./shared/json";

const FONT_TITLE = 22;
const FONT_VALUE = 24;
const FONT_AXIS = 20;

// 圖 A
const BAR_A_FILL = "#C5D2DB";
const DOT_A_FILL = "#1F5673";
const BAND_FILL = "#CDE3D2";
// 目前實際 EPS：橘色，刻意與假設用的灰藍分開——上面幾條是「你給的倍數
// 需要賺多少」，這一條是「現在真的賺多少」，同色會讓人以為都是假設。
const CURRENT_FILL = "#E8A33D";
const CURRENT_TEXT = "#8A5A12";
// 圖 B：顏色編碼的是「買入價」，不是損益方向。
// 刻意不套用專案語意色（虧損紅／獲利綠）——若套用，同一買入價的三條長條會因正負
// 而變色，讀者會誤以為顏色代表盈虧而非入場價，整張圖的對照邏輯就毀了。
const ENTRY_A_FILL = "#2E6C8E";
const ENTRY_B_FILL = "#B5654A";
const ZERO_LINE = "#26333C";

let annotationRegistered = false;

function registerAnnotation(): void {
  if (annotationRegistered) return;
  const plugin = window["chartjs-plugin-annotation"];
  if (!plugin) return;
  Chart.register(plugin);
  annotationRegistered = true;
}

function parsePayload(raw: string | undefined): Record<string, unknown> | null {
  if (!raw) return null;
  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch {
    return null;
  }
  return isRecord(parsed) ? parsed : null;
}

function numbersOf(value: unknown, key: string): number[] {
  if (!Array.isArray(value)) return [];
  return value
    .map((row) => (isRecord(row) ? row[key] : null))
    .filter((n): n is number => typeof n === "number");
}

/** ASCII hyphen-minus，禁 U+2212（規格 §S1 格式化規則）。 */
function pct(value: number): string {
  const sign = value >= 0 ? "+" : "-";
  return `${sign}${Math.abs(value * 100).toFixed(1)}%`;
}

function money(value: number): string {
  return `$${value.toFixed(2)}`;
}

// ── 圖 A ────────────────────────────────────────────────

/**
 * x 軸上限。
 *
 * 規格 §S5 訂的是「max(required_eps) * 1.15，取最接近的 5 的倍數」，
 * 那條規則是照 EPS 約 7–9 的預設情境寫的：8.94 → 10.28 → 10，剛好。
 * 但 EPS 小的股票會被它毀掉——SHOP 的 EPS 約 1.5，同一條規則得到軸上限 5，
 * 資料只佔軸的 41%，長條全擠在左邊。
 *
 * 改成刻度單位隨數量級縮放：> 5 沿用規格的 5 的倍數（預設情境行為不變），
 * ≤ 5 改用 0.5、≤ 1 改用 0.1。
 *
 * 色帶也要一起算進去：帶高於所有長條時（現有預測遠超需求就會這樣），
 * 只看長條會把色帶切掉一半。
 */
export function axisMax(
  values: number[],
  bandHigh: number | null = null,
): number {
  const dataMax = Math.max(...values);
  // 長條留 15% 餘裕給右側的數值標籤；色帶只需要一點點，它沒有標籤。
  const raw = Math.max(dataMax * 1.15, bandHigh !== null ? bandHigh * 1.08 : 0);

  if (raw > 5) {
    // 規格原文的行為：取最接近的 5 的倍數，不足以容納資料就往上加。
    let bound = Math.round(raw / 5) * 5;
    while (bound < dataMax || (bandHigh !== null && bound < bandHigh))
      bound += 5;
    return bound;
  }

  const unit = raw > 1 ? 0.5 : 0.1;
  const bound = Math.ceil(raw / unit) * unit;
  // 浮點誤差會讓 2.5 變成 2.5000000000000004，進到 Chart.js 的刻度計算會很難看。
  return Math.round(bound * 100) / 100;
}

function hasBandValue(payload: Record<string, unknown>): number | null {
  return typeof payload.bandHigh === "number" ? payload.bandHigh : null;
}

function renderChartA(
  canvas: HTMLCanvasElement,
  payload: Record<string, unknown>,
): void {
  const rows = Array.isArray(payload.rows) ? payload.rows : [];
  const multiples = numbersOf(rows, "multiple");
  const required = numbersOf(rows, "requiredEps");
  if (required.length === 0) return;

  // 由上而下依 multiple 由大到小。
  // tsconfig 開了 noUncheckedIndexedAccess，索引存取是 number | undefined，
  // 所以在配對階段就把缺值的濾掉，而不是之後再到處補 ?? 0。
  const order = multiples
    .map((m, i) => ({ m, eps: required[i] }))
    .filter((o): o is { m: number; eps: number } => typeof o.eps === "number")
    .sort((x, y) => y.m - x.m);

  const currentEps =
    typeof payload.currentEps === "number" && payload.currentEps > 0
      ? payload.currentEps
      : null;

  const labels = order.map((o) => `${o.m} 倍`);
  const values = order.map((o) => o.eps);
  // 目前 EPS 排在最後一列，與假設分開；軸上限要把它一起算進去，
  // 否則實際 EPS 高於所有假設時那條會被切掉。
  if (currentEps !== null) {
    labels.push("目前 TTM EPS（實際）");
    values.push(currentEps);
  }
  const max = axisMax(values, hasBandValue(payload));
  const barColors = values.map((_, i) =>
    currentEps !== null && i === values.length - 1 ? CURRENT_FILL : BAR_A_FILL,
  );
  const dotColors = values.map((_, i) =>
    currentEps !== null && i === values.length - 1 ? CURRENT_TEXT : DOT_A_FILL,
  );

  const bandLow = typeof payload.bandLow === "number" ? payload.bandLow : null;
  const bandHigh =
    typeof payload.bandHigh === "number" ? payload.bandHigh : null;
  const hasBand = bandLow !== null && bandHigh !== null;
  if (hasBand) registerAnnotation();

  const fiscalYear =
    typeof payload.fiscalYear === "string" ? payload.fiscalYear : "";
  const bandLabel =
    typeof payload.bandLabel === "string" ? payload.bandLabel : "";

  // 圖上有兩個年度：長條與標題是「本財政年度的門檻」，綠帶是「下一財政
  // 年度的預測」。標題只寫其中一個，看的人會把整張圖都當成那一年。
  // 綠帶的年度從它自己的來源標籤取，不是從標題年度推——兩者本來就不同。
  const bandYear = bandLabel.match(/\d{4}/)?.[0] ?? null;
  const chartTitle =
    hasBand && bandYear !== null
      ? `${fiscalYear} 需要的 EPS　｜　綠帶＝FY${bandYear} 分析師預測`
      : `${fiscalYear} 需要的 EPS`;

  new Chart(canvas, {
    type: "bar",
    data: {
      labels,
      datasets: [
        { data: values, backgroundColor: barColors, borderWidth: 0, order: 2 },
        {
          type: "scatter",
          data: values.map((v, i) => ({ x: v, y: i })),
          backgroundColor: dotColors,
          pointRadius: 7,
          order: 1,
        },
      ],
    },
    options: {
      indexAxis: "y",
      responsive: true,
      maintainAspectRatio: false,
      layout: { padding: { right: 72 } },
      plugins: {
        legend: { display: false },
        title: {
          display: true,
          text: chartTitle,
          font: { size: FONT_TITLE, weight: "500" },
        },
        tooltip: { enabled: false },
        // 色帶繪製層級在橫條之上
        annotation: hasBand
          ? {
              annotations: {
                band: {
                  type: "box",
                  xMin: bandLow,
                  xMax: bandHigh,
                  backgroundColor: BAND_FILL,
                  borderWidth: 0,
                  drawTime: "afterDatasetsDraw",
                },
              },
            }
          : {},
        datalabels: false,
      },
      scales: {
        x: {
          min: 0,
          max,
          ticks: {
            font: { size: FONT_AXIS },
            // 0.1 一格：格線畫得細，標籤由 autoSkip 依可用寬度自行疏化，
            // 不會在 0–10 的軸上硬印一百個數字。
            stepSize: 0.1,
            autoSkip: true,
            maxRotation: 0,
          },
          title: {
            display: true,
            text: "所需 EPS（美元）",
            font: { size: FONT_AXIS },
          },
        },
        y: { ticks: { font: { size: FONT_AXIS } } },
      },
    },
    plugins: [valueLabelPlugin(values.map(money), dotColors)],
  });
}

/** 圓點右側標數值。Chart.js 沒有內建 datalabels，用 afterDatasetsDraw 自己畫。 */
function valueLabelPlugin(
  labels: string[],
  colors: string[],
): Record<string, unknown> {
  return {
    id: "priceInValueLabels",
    afterDatasetsDraw(chart: ChartInstance): void {
      const ctx = chart.canvas.getContext("2d");
      if (!ctx) return;
      const meta = chart.getDatasetMeta(1);
      ctx.save();
      ctx.font = `700 ${FONT_VALUE}px sans-serif`;
      ctx.textBaseline = "middle";
      meta.data.forEach((point, i) => {
        const text = labels[i];
        if (!text) return;
        ctx.fillStyle = colors[i] ?? DOT_A_FILL;
        ctx.fillText(text, point.x + 14, point.y);
      });
      ctx.restore();
    },
  };
}

// ── 圖 B ────────────────────────────────────────────────

function renderChartB(
  canvas: HTMLCanvasElement,
  payload: Record<string, unknown>,
): void {
  const rows = Array.isArray(payload.rows) ? payload.rows : [];
  if (rows.length === 0) return;

  const entryA = isRecord(payload.entryA) ? payload.entryA : {};
  const entryB = isRecord(payload.entryB) ? payload.entryB : {};
  const labelA = typeof entryA.label === "string" ? entryA.label : "買入基準";
  const labelB = typeof entryB.label === "string" ? entryB.label : "假設買入價";

  const ordered = [...rows]
    .filter(isRecord)
    .sort((a, b) => Number(b.multiple) - Number(a.multiple));

  const labels = ordered.map((r) => {
    const target =
      typeof r.targetPrice === "number" ? money(r.targetPrice) : "";
    return [`${String(r.multiple)} 倍`, `對應 ${target}`];
  });

  const seriesFor = (idx: number): number[] =>
    ordered.map((r) => {
      const returns = Array.isArray(r.returns) ? r.returns : [];
      const cell = returns[idx];
      return isRecord(cell) && typeof cell.totalReturn === "number"
        ? cell.totalReturn
        : 0;
    });

  const a = seriesFor(0);
  const b = seriesFor(1);
  const span = Math.max(...[...a, ...b].map(Math.abs), 0.05) * 1.25;

  new Chart(canvas, {
    type: "bar",
    data: {
      labels,
      datasets: [
        {
          label: labelA,
          data: a,
          backgroundColor: ENTRY_A_FILL,
          borderWidth: 0,
          minBarLength: 3,
        },
        {
          label: labelB,
          data: b,
          backgroundColor: ENTRY_B_FILL,
          borderWidth: 0,
          minBarLength: 3,
        },
      ],
    },
    options: {
      indexAxis: "y",
      responsive: true,
      maintainAspectRatio: false,
      // 組間留白 ≥ 組內間距 2 倍
      categoryPercentage: 0.6,
      barPercentage: 0.9,
      plugins: {
        legend: { display: true, labels: { font: { size: FONT_AXIS } } },
        title: { display: false },
        tooltip: { enabled: false },
        annotation: {},
      },
      scales: {
        x: {
          min: -span,
          max: span,
          ticks: {
            font: { size: FONT_AXIS },
            callback: (value: number | undefined) =>
              typeof value === "number" ? pct(value) : "",
          },
          grid: {
            color: (ctx: { tick?: { value: number } }) =>
              ctx.tick?.value === 0 ? ZERO_LINE : "rgba(0,0,0,0.06)",
            lineWidth: (ctx: { tick?: { value: number } }) =>
              ctx.tick?.value === 0 ? 1.5 : 1,
          },
          title: {
            display: true,
            text: xAxisTitle(payload),
            font: { size: FONT_AXIS },
          },
        },
        y: { ticks: { font: { size: FONT_AXIS } } },
      },
    },
    plugins: [groupedLabelPlugin([a, b])],
  });
}

function xAxisTitle(payload: Record<string, unknown>): string {
  const years = payload.holdingYears;
  const base = "總報酬";
  return typeof years === "number" && years > 0
    ? `${base}（持有 ${years} 年）`
    : base;
}

/**
 * 長條夠長時數值置內側（白字），過短時置外側（深色）。
 *
 * 用長條的實際像素長度判斷，不用數值大小猜——`-1.4%` 在寬螢幕上可能比
 * `+62.7%` 在窄螢幕上還長。
 */
function groupedLabelPlugin(series: number[][]): Record<string, unknown> {
  const PADDING = 12;

  return {
    id: "priceInGroupedLabels",
    afterDatasetsDraw(chart: ChartInstance): void {
      const ctx = chart.canvas.getContext("2d");
      const xScale = chart.scales.x;
      if (!ctx || !xScale) return;

      const zeroX = xScale.getPixelForValue(0);
      ctx.save();
      ctx.font = `700 ${FONT_VALUE}px sans-serif`;
      ctx.textBaseline = "middle";

      series.forEach((values, dsIndex) => {
        chart.getDatasetMeta(dsIndex).data.forEach((bar, i) => {
          const value = values[i];
          if (typeof value !== "number") return;

          const text = pct(value);
          const textW = ctx.measureText(text).width;
          const barLen = Math.abs(bar.x - zeroX);
          const positive = value >= 0;
          const inside = barLen > textW + PADDING * 2;

          ctx.fillStyle = inside ? "#FFFFFF" : ZERO_LINE;
          if (inside) {
            ctx.textAlign = positive ? "right" : "left";
            ctx.fillText(text, bar.x + (positive ? -PADDING : PADDING), bar.y);
          } else {
            ctx.textAlign = positive ? "left" : "right";
            ctx.fillText(text, bar.x + (positive ? PADDING : -PADDING), bar.y);
          }
        });
      });
      ctx.restore();
    },
  };
}

// ── 掛載 ────────────────────────────────────────────────

export function init(root: HTMLElement): void {
  if (!(root instanceof HTMLCanvasElement)) return;

  const a = parsePayload(root.dataset.chartAPayload);
  if (a) {
    renderChartA(root, a);
    return;
  }

  const b = parsePayload(root.dataset.chartBPayload);
  if (b) {
    renderChartB(root, b);
  }
}
