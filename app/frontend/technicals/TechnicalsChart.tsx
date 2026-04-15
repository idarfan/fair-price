import { useEffect, useRef, useState } from "react";
import {
  createChart,
  ColorType,
  LineStyle,
  CrosshairMode,
  type IChartApi,
  type UTCTimestamp,
  type Time,
} from "lightweight-charts";

interface DataPoint {
  time: string | number;
  date: string;
  open: number;
  high: number;
  low: number;
  close: number;
  volume: number;
  ma20: number | null;
  ma50: number | null;
  rsi14: number | null;
  rsi7: number | null;
  avg_vol: number;
}

interface Stats {
  rsi14: number | null;
  rsi7: number | null;
  rsi14_label: string;
  rsi7_label: string;
  ma20_price: number | null;
  ma20_dist_pct: number | null;
  pos_52w_pct: number;
  high_range: number;
  low_range: number;
  today_vol: number;
  avg_vol: number;
  vol_ratio_pct: number;
  vol_label: string;
}

interface SupportResistance {
  short_support: number | null;
  mid_support: number | null;
  strong_support: number | null;
  short_resistance: number | null;
  strong_resistance: number | null;
}

const EMPTY_SR: SupportResistance = {
  short_support: null,
  mid_support: null,
  strong_support: null,
  short_resistance: null,
  strong_resistance: null,
};

// 5 named S/R lines — warm colours above price (resistance), cool below (support)
// All colours chosen for high contrast on dark background #1e293b
const SR_LINES: {
  key: keyof SupportResistance;
  label: string;
  color: string;
  lineWidth: 1 | 2;
}[] = [
  { key: "strong_resistance", label: "強阻力", color: "#dc2626", lineWidth: 2 }, // red-600, bold
  {
    key: "short_resistance",
    label: "短線阻力",
    color: "#f97316",
    lineWidth: 1,
  }, // orange-500
  { key: "short_support", label: "短線支撐", color: "#34d399", lineWidth: 1 }, // emerald-400
  { key: "mid_support", label: "中線支撐", color: "#22d3ee", lineWidth: 1 }, // cyan-400
  { key: "strong_support", label: "強支撐", color: "#818cf8", lineWidth: 2 }, // indigo-400, bold
];

type Range = "1d" | "5d" | "1m" | "3m" | "6m" | "1y";

const RANGES: { key: Range; label: string }[] = [
  { key: "1d", label: "1D" },
  { key: "5d", label: "5D" },
  { key: "1m", label: "1M" },
  { key: "3m", label: "3M" },
  { key: "6m", label: "6M" },
  { key: "1y", label: "1Y" },
];

const INTRADAY: Range[] = ["1d", "5d"];

function toTime(t: string | number): Time {
  return typeof t === "number" ? (t as UTCTimestamp) : t;
}

function rsiColor(v: number | null): string {
  if (v === null) return "#94a3b8";
  if (v >= 70) return "#f87171";
  if (v <= 30) return "#4ade80";
  if (v >= 50) return "#fbbf24";
  return "#94a3b8";
}

function distColor(v: number | null): string {
  if (v === null) return "#94a3b8";
  return v >= 0 ? "#4ade80" : "#f87171";
}

function fmtVol(v: number): string {
  if (v >= 1e9) return (v / 1e9).toFixed(1) + "B";
  if (v >= 1e6) return (v / 1e6).toFixed(0) + "M";
  return (v / 1e3).toFixed(0) + "K";
}

function StatCard({
  label,
  value,
  sub,
  valueColor,
}: {
  label: string;
  value: string;
  sub: string;
  valueColor?: string;
}) {
  return (
    <div
      style={{ background: "#0f172a", borderRadius: 8, padding: "10px 12px" }}
    >
      <div style={{ fontSize: 11, color: "#94a3b8", marginBottom: 3 }}>
        {label}
      </div>
      <div
        style={{
          fontSize: 15,
          fontWeight: 500,
          color: valueColor ?? "#e2e8f0",
        }}
      >
        {value}
      </div>
      <div style={{ fontSize: 11, color: "#64748b", marginTop: 2 }}>{sub}</div>
    </div>
  );
}

const CHART_OPTS = {
  layout: {
    background: { type: ColorType.Solid, color: "#1e293b" },
    textColor: "#64748b",
  },
  grid: {
    vertLines: { color: "#1e293b" },
    horzLines: { color: "#243347" },
  },
  crosshair: { mode: CrosshairMode.Normal },
  rightPriceScale: { borderColor: "#334155" },
  timeScale: { borderColor: "#334155" },
  handleScroll: true,
  handleScale: true,
};

export default function TechnicalsChart({ symbol }: { symbol: string }) {
  const [range, setRange] = useState<Range>("1m");
  const [data, setData] = useState<DataPoint[]>([]);
  const [stats, setStats] = useState<Stats | null>(null);
  const [sr, setSr] = useState<SupportResistance>(EMPTY_SR);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(false);

  const priceRef = useRef<HTMLDivElement>(null);
  const volRef = useRef<HTMLDivElement>(null);
  const rsiRef = useRef<HTMLDivElement>(null);

  // ── Fetch ──────────────────────────────────────────────────────────
  useEffect(() => {
    setLoading(true);
    setError(false);
    setData([]);
    fetch(`/api/v1/charts/${encodeURIComponent(symbol)}?range=${range}`)
      .then((r) => {
        if (!r.ok) throw new Error("fetch failed");
        return r.json() as Promise<{
          data: DataPoint[];
          stats: Stats;
          support_resistance: SupportResistance;
        }>;
      })
      .then((json) => {
        setData(json.data);
        setStats(json.stats);
        setSr(json.support_resistance ?? EMPTY_SR);
        setLoading(false);
      })
      .catch(() => {
        setError(true);
        setLoading(false);
      });
  }, [symbol, range]);

  // ── Charts ─────────────────────────────────────────────────────────
  useEffect(() => {
    if (!priceRef.current || !volRef.current || !rsiRef.current) return;
    if (data.length === 0) return;

    const intraday = INTRADAY.includes(range);
    const w = priceRef.current.offsetWidth || 600;

    // ── Price chart ──
    const priceChart: IChartApi = createChart(priceRef.current, {
      ...CHART_OPTS,
      width: w,
      height: 280,
      timeScale: {
        ...CHART_OPTS.timeScale,
        timeVisible: intraday,
        secondsVisible: false,
      },
    });

    const candleSeries = priceChart.addCandlestickSeries({
      upColor: "#4ade80",
      downColor: "#f87171",
      borderVisible: false,
      wickUpColor: "#4ade80",
      wickDownColor: "#f87171",
    });
    candleSeries.setData(
      data.map((d) => ({
        time: toTime(d.time),
        open: d.open,
        high: d.high,
        low: d.low,
        close: d.close,
      })),
    );

    const ma20Data = data
      .filter((d) => d.ma20 != null)
      .map((d) => ({ time: toTime(d.time), value: d.ma20! }));
    if (ma20Data.length > 0) {
      const ma20 = priceChart.addLineSeries({
        color: "#fbbf24",
        lineWidth: 1,
        priceLineVisible: false,
        lastValueVisible: false,
      });
      ma20.setData(ma20Data);
    }

    const ma50Data = data
      .filter((d) => d.ma50 != null)
      .map((d) => ({ time: toTime(d.time), value: d.ma50! }));
    if (ma50Data.length > 0) {
      const ma50 = priceChart.addLineSeries({
        color: "#f87171",
        lineWidth: 1,
        priceLineVisible: false,
        lastValueVisible: false,
      });
      ma50.setData(ma50Data);
    }

    // S&R price lines — 5 named levels, each rendered only if non-null
    SR_LINES.forEach(({ key, label, color, lineWidth }) => {
      const price = sr[key];
      if (price == null) return;
      candleSeries.createPriceLine({
        price,
        color,
        lineWidth,
        lineStyle: LineStyle.Dashed,
        axisLabelVisible: true,
        title: `${label} $${price}`,
      });
    });

    priceChart.timeScale().fitContent();

    // ── Volume chart ──
    const volChart: IChartApi = createChart(volRef.current, {
      ...CHART_OPTS,
      width: w,
      height: 80,
      timeScale: { ...CHART_OPTS.timeScale, timeVisible: false },
      rightPriceScale: {
        ...CHART_OPTS.rightPriceScale,
        scaleMargins: { top: 0.1, bottom: 0 },
      },
    });

    let prevClose: number | null = null;
    const volSeries = volChart.addHistogramSeries({
      priceFormat: { type: "volume" },
      priceLineVisible: false,
      lastValueVisible: false,
    });
    volSeries.setData(
      data.map((d) => {
        const color =
          d.close >= (prevClose ?? d.close)
            ? "rgba(74,222,128,0.65)"
            : "rgba(248,113,113,0.65)";
        prevClose = d.close;
        return { time: toTime(d.time), value: d.volume, color };
      }),
    );

    const avgVolSeries = volChart.addLineSeries({
      color: "#f59e0b",
      lineWidth: 1,
      lineStyle: LineStyle.Dashed,
      priceLineVisible: false,
      lastValueVisible: false,
    });
    avgVolSeries.setData(
      data.map((d) => ({ time: toTime(d.time), value: d.avg_vol })),
    );
    volChart.timeScale().fitContent();

    // ── RSI chart ──
    const rsiChart: IChartApi = createChart(rsiRef.current, {
      ...CHART_OPTS,
      width: w,
      height: 80,
      timeScale: { ...CHART_OPTS.timeScale, timeVisible: false },
      rightPriceScale: {
        ...CHART_OPTS.rightPriceScale,
        scaleMargins: { top: 0.1, bottom: 0.1 },
      },
    });

    const rsi14Data = data
      .filter((d) => d.rsi14 != null)
      .map((d) => ({ time: toTime(d.time), value: d.rsi14! }));
    const rsi7Data = data
      .filter((d) => d.rsi7 != null)
      .map((d) => ({ time: toTime(d.time), value: d.rsi7! }));

    if (rsi14Data.length > 0) {
      const rsi14 = rsiChart.addLineSeries({
        color: "#a78bfa",
        lineWidth: 2,
        priceLineVisible: false,
        lastValueVisible: true,
        title: "RSI14",
      });
      rsi14.setData(rsi14Data);
      rsi14.createPriceLine({
        price: 70,
        color: "#f87171",
        lineWidth: 1,
        lineStyle: LineStyle.Dashed,
        axisLabelVisible: false,
        title: "── 超買 70",
      });
      rsi14.createPriceLine({
        price: 30,
        color: "#4ade80",
        lineWidth: 1,
        lineStyle: LineStyle.Dashed,
        axisLabelVisible: false,
        title: "── 超賣 30",
      });
    }
    if (rsi7Data.length > 0) {
      const rsi7 = rsiChart.addLineSeries({
        color: "#38bdf8",
        lineWidth: 1,
        priceLineVisible: false,
        lastValueVisible: true,
        title: "RSI7",
      });
      rsi7.setData(rsi7Data);
    }
    rsiChart.timeScale().fitContent();

    // ── Sync time scales ──
    let syncing = false;
    const sync = (src: IChartApi, targets: IChartApi[]) => {
      src.timeScale().subscribeVisibleLogicalRangeChange((r) => {
        if (syncing || r === null) return;
        syncing = true;
        targets.forEach((c) => c.timeScale().setVisibleLogicalRange(r));
        syncing = false;
      });
    };
    sync(priceChart, [volChart, rsiChart]);
    sync(volChart, [priceChart, rsiChart]);
    sync(rsiChart, [priceChart, volChart]);

    // ── Resize ──
    let removed = false;
    const observer = new ResizeObserver(() => {
      if (removed) return;
      const rw = priceRef.current?.offsetWidth ?? 0;
      if (rw === 0) return;
      priceChart.applyOptions({ width: rw });
      volChart.applyOptions({ width: rw });
      rsiChart.applyOptions({ width: rw });
    });
    if (priceRef.current) observer.observe(priceRef.current);

    return () => {
      removed = true;
      observer.disconnect();
      priceChart.remove();
      volChart.remove();
      rsiChart.remove();
    };
  }, [data, sr, range]);

  const volLabel = stats?.vol_label ?? "";
  const volBadgeColor =
    volLabel === "爆量" || volLabel === "放量"
      ? "#4ade80"
      : volLabel === "縮量"
        ? "#f87171"
        : "#94a3b8";

  return (
    <div
      style={{
        background: "#1e293b",
        borderRadius: 12,
        padding: 16,
        fontFamily: "system-ui, sans-serif",
      }}
    >
      {/* Range tabs */}
      <div style={{ display: "flex", gap: 6, marginBottom: 14 }}>
        {RANGES.map((r) => (
          <button
            key={r.key}
            onClick={() => setRange(r.key)}
            style={{
              padding: "4px 14px",
              borderRadius: 6,
              fontSize: 12,
              border: "none",
              cursor: "pointer",
              background: range === r.key ? "#3b82f6" : "#0f172a",
              color: range === r.key ? "#fff" : "#94a3b8",
            }}
          >
            {r.label}
          </button>
        ))}
      </div>

      {/* Stat cards */}
      {stats && (
        <div
          style={{
            display: "grid",
            gridTemplateColumns: "repeat(4,1fr)",
            gap: 10,
            marginBottom: 14,
          }}
        >
          <StatCard
            label="RSI (14) / (7)"
            value={`${stats.rsi14 ?? "—"} / ${stats.rsi7 ?? "—"}`}
            sub={`${stats.rsi14_label} / ${stats.rsi7_label}`}
            valueColor={rsiColor(stats.rsi14)}
          />
          <StatCard
            label="MA20 距離"
            value={
              stats.ma20_dist_pct != null
                ? `${stats.ma20_dist_pct > 0 ? "+" : ""}${stats.ma20_dist_pct}%`
                : "—"
            }
            sub={stats.ma20_price != null ? `MA20 = $${stats.ma20_price}` : "—"}
            valueColor={distColor(stats.ma20_dist_pct)}
          />
          <StatCard
            label="52W 位置"
            value={`${stats.pos_52w_pct}%`}
            sub={`$${stats.low_range} — $${stats.high_range}`}
          />
          <StatCard
            label="成交量"
            value={fmtVol(stats.today_vol)}
            sub={`均量 ${fmtVol(stats.avg_vol)}，今日 ${stats.vol_ratio_pct}%`}
            valueColor={
              stats.vol_ratio_pct >= 130
                ? "#4ade80"
                : stats.vol_ratio_pct <= 60
                  ? "#f87171"
                  : "#e2e8f0"
            }
          />
        </div>
      )}

      {loading && (
        <div
          style={{
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            height: 460,
            color: "#64748b",
            fontSize: 13,
          }}
        >
          載入中...
        </div>
      )}
      {error && (
        <div
          style={{
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            height: 460,
            color: "#f87171",
            fontSize: 13,
          }}
        >
          資料載入失敗，請稍後重試
        </div>
      )}

      {/* Charts — always rendered so refs are available; hidden while loading */}
      <div style={{ display: loading || error ? "none" : "block" }}>
        {/* Price: candlestick + MA + S/R */}
        <div
          style={{
            fontSize: 11,
            color: "#94a3b8",
            marginBottom: 4,
            display: "flex",
            gap: 14,
            alignItems: "center",
            flexWrap: "wrap",
          }}
        >
          K線 + MA20 + MA50
          {SR_LINES.filter((l) => sr[l.key] != null).map((l) => (
            <span key={l.key} style={{ color: l.color }}>
              ── {l.label}
            </span>
          ))}
        </div>
        {/* S/R 文字摘要：永遠可見，不依賴圖表 axis（解決線在可視範圍外時看不到標籤的問題） */}
        {SR_LINES.some((l) => sr[l.key] != null) && data.length > 0 && (
          <div
            style={{
              display: "flex",
              gap: 10,
              flexWrap: "wrap",
              marginBottom: 6,
              padding: "4px 8px",
              background: "#0f172a",
              borderRadius: 6,
              fontSize: 11,
            }}
          >
            {SR_LINES.filter((l) => sr[l.key] != null).map((l) => {
              const price = sr[l.key]!;
              const lastClose = data[data.length - 1]?.close;
              const dist =
                lastClose && lastClose > 0
                  ? (((price - lastClose) / lastClose) * 100).toFixed(1)
                  : null;
              return (
                <span
                  key={l.key}
                  style={{ color: l.color, whiteSpace: "nowrap" }}
                >
                  {l.label} <span style={{ fontWeight: 600 }}>${price}</span>
                  {dist !== null && (
                    <span style={{ color: "#64748b", marginLeft: 2 }}>
                      ({Number(dist) > 0 ? "+" : ""}
                      {dist}%)
                    </span>
                  )}
                </span>
              );
            })}
          </div>
        )}
        <div ref={priceRef} style={{ width: "100%" }} />

        {/* Volume */}
        <div
          style={{
            fontSize: 11,
            color: "#94a3b8",
            marginTop: 10,
            marginBottom: 4,
            display: "flex",
            alignItems: "center",
            gap: 8,
          }}
        >
          成交量
          <span
            style={{
              fontSize: 10,
              padding: "1px 6px",
              borderRadius: 4,
              fontWeight: 500,
              background:
                volLabel === "爆量" || volLabel === "放量"
                  ? "rgba(74,222,128,0.15)"
                  : volLabel === "縮量"
                    ? "rgba(248,113,113,0.15)"
                    : "rgba(148,163,184,0.15)",
              color: volBadgeColor,
            }}
          >
            {volLabel}
          </span>
          {stats && (
            <span style={{ fontSize: 11, color: "#64748b" }}>
              今日 {stats.vol_ratio_pct}% 均量
            </span>
          )}
        </div>
        <div ref={volRef} style={{ width: "100%" }} />

        {/* RSI */}
        <div
          style={{
            fontSize: 11,
            color: "#94a3b8",
            marginTop: 10,
            marginBottom: 4,
          }}
        >
          RSI (14) / RSI (7) — 超買 &gt;70 / 超賣 &lt;30
        </div>
        <div ref={rsiRef} style={{ width: "100%" }} />
      </div>
    </div>
  );
}
