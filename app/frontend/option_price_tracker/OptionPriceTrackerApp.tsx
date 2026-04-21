import { useCallback, useEffect, useState } from "react";
import TickerSidebar from "./components/TickerSidebar";
import ExpirationTabs from "./components/ExpirationTabs";
import SnapshotDateTabs from "./components/SnapshotDateTabs";
import OptionsChainTable, {
  type StrikeRow,
} from "./components/OptionsChainTable";
import PremiumTrendChart from "./components/PremiumTrendChart";
import type {
  TrackedTicker,
  OptionSnapshotRow,
  PremiumTrendPoint,
} from "./types";

function csrfToken(): string {
  return (
    (document.querySelector('meta[name="csrf-token"]') as HTMLMetaElement)
      ?.content ?? ""
  );
}

function calcDte(expiration: string): number {
  const today = new Date();
  today.setHours(0, 0, 0, 0);
  const exp = new Date(expiration);
  return Math.round((exp.getTime() - today.getTime()) / 86_400_000);
}

function usMarketHolidays(year: number): Set<string> {
  const fmt = (d: Date) => d.toISOString().slice(0, 10);
  const nearestWeekday = (d: Date): Date => {
    const day = d.getDay();
    if (day === 0) return new Date(d.getTime() + 86_400_000);
    if (day === 6) return new Date(d.getTime() - 86_400_000);
    return d;
  };
  const nthWeekday = (
    y: number,
    month: number,
    weekday: number,
    n: number,
  ): Date => {
    const d = new Date(y, month, 1);
    let count = 0;
    while (true) {
      if (d.getDay() === weekday && ++count === n) return new Date(d);
      d.setDate(d.getDate() + 1);
    }
  };
  const lastWeekday = (y: number, month: number, weekday: number): Date => {
    const d = new Date(y, month + 1, 0);
    while (d.getDay() !== weekday) d.setDate(d.getDate() - 1);
    return new Date(d);
  };
  // Easter (Anonymous Gregorian algorithm)
  const easterDate = (() => {
    const a = year % 19,
      b = Math.floor(year / 100),
      c = year % 100;
    const d = Math.floor(b / 4),
      e = b % 4,
      f = Math.floor((b + 8) / 25);
    const g = Math.floor((b - f + 1) / 3);
    const h = (19 * a + b - d - g + 15) % 30;
    const i = Math.floor(c / 4),
      k = c % 4;
    const l = (32 + 2 * e + 2 * i - h - k) % 7;
    const m = Math.floor((a + 11 * h + 22 * l) / 451);
    const month = Math.floor((h + l - 7 * m + 114) / 31) - 1;
    const day = ((h + l - 7 * m + 114) % 31) + 1;
    return new Date(year, month, day);
  })();
  const goodFriday = new Date(easterDate.getTime() - 2 * 86_400_000);

  return new Set([
    fmt(nearestWeekday(new Date(year, 0, 1))), // New Year's Day
    fmt(nthWeekday(year, 0, 1, 3)), // MLK Day (3rd Mon Jan)
    fmt(nthWeekday(year, 1, 1, 3)), // Presidents' Day (3rd Mon Feb)
    fmt(goodFriday), // Good Friday
    fmt(lastWeekday(year, 4, 1)), // Memorial Day (last Mon May)
    fmt(nearestWeekday(new Date(year, 5, 19))), // Juneteenth
    fmt(nearestWeekday(new Date(year, 6, 4))), // Independence Day
    fmt(nthWeekday(year, 8, 1, 1)), // Labor Day (1st Mon Sep)
    fmt(nthWeekday(year, 10, 4, 4)), // Thanksgiving (4th Thu Nov)
    fmt(nearestWeekday(new Date(year, 11, 25))), // Christmas
  ]);
}

function calcTradingDays(expiration: string): number {
  const today = new Date();
  today.setHours(0, 0, 0, 0);
  const exp = new Date(expiration);
  exp.setHours(0, 0, 0, 0);
  if (exp <= today) return 0;
  const holidays = new Set<string>();
  for (let y = today.getFullYear(); y <= exp.getFullYear(); y++) {
    usMarketHolidays(y).forEach((h) => holidays.add(h));
  }
  let count = 0;
  const cur = new Date(today);
  cur.setDate(cur.getDate() + 1);
  while (cur <= exp) {
    const day = cur.getDay();
    if (day !== 0 && day !== 6 && !holidays.has(cur.toISOString().slice(0, 10)))
      count++;
    cur.setDate(cur.getDate() + 1);
  }
  return count;
}

function buildChainRows(
  snapshots: OptionSnapshotRow[],
  expiration: string,
  underlyingPrice = 0,
  nearCount = 6,
): StrikeRow[] {
  const filtered = snapshots.filter((s) => s.expiration === expiration);
  let strikes = [...new Set(filtered.map((s) => s.strike))].sort(
    (a, b) => a - b,
  );

  if (underlyingPrice > 0) {
    const below = strikes.filter((s) => s <= underlyingPrice).slice(-nearCount);
    const above = strikes
      .filter((s) => s > underlyingPrice)
      .slice(0, nearCount);
    strikes = [...below, ...above];
  }

  return strikes.map((strike) => ({
    strike,
    call:
      filtered.find((s) => s.strike === strike && s.option_type === "call") ??
      null,
    put:
      filtered.find((s) => s.strike === strike && s.option_type === "put") ??
      null,
  }));
}

interface Props {
  initialTickers: TrackedTicker[];
}

export default function OptionPriceTrackerApp({ initialTickers }: Props) {
  const [tickers, setTickers] = useState<TrackedTicker[]>(initialTickers);
  const [selected, setSelected] = useState<TrackedTicker | null>(
    initialTickers[0] ?? null,
  );

  const [snapshots, setSnapshots] = useState<OptionSnapshotRow[]>([]);
  const [expirations, setExpirations] = useState<string[]>([]);
  const [selectedExp, setSelectedExp] = useState("");
  const [snapshotDate, setSnapshotDate] = useState<string | null>(null);
  const [availableDates, setAvailableDates] = useState<string[]>([]);
  const [underlyingPrice, setUnderlyingPrice] = useState(0);
  const [callPutFilter, setCallPutFilter] = useState<"both" | "call" | "put">(
    "both",
  );

  const [selectedContract, setSelectedContract] = useState<string | null>(null);
  const [trendData, setTrendData] = useState<PremiumTrendPoint[]>([]);

  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const loadSnapshots = useCallback(
    async (ticker: TrackedTicker, date?: string) => {
      setLoading(true);
      setError(null);
      setSelectedContract(null);
      setTrendData([]);
      try {
        const params = new URLSearchParams();
        if (date) {
          params.set("snapshot_date", date);
        } else {
          params.set("latest_only", "true");
        }
        const res = await fetch(
          `/api/v1/option_snapshots/${encodeURIComponent(ticker.symbol)}?${params}`,
        );
        if (!res.ok) {
          const json = (await res.json().catch(() => ({}))) as {
            error?: string;
          };
          setError(json.error ?? "載入失敗");
          return;
        }
        const json = (await res.json()) as {
          snapshots: OptionSnapshotRow[];
          expirations: string[];
          latest_snapshot_date: string | null;
          available_dates: string[];
        };
        setSnapshots(json.snapshots);
        setExpirations(json.expirations);
        setSnapshotDate(json.latest_snapshot_date);
        setAvailableDates(json.available_dates ?? []);
        setSelectedExp(json.expirations[0] ?? "");
        const price = json.snapshots[0]?.underlying_price ?? 0;
        setUnderlyingPrice(price);
      } catch {
        setError("網路錯誤，請稍後再試");
      } finally {
        setLoading(false);
      }
    },
    [],
  );

  async function loadTrend(contractSymbol: string) {
    if (!selected) return;
    setSelectedContract(contractSymbol);
    try {
      const res = await fetch(
        `/api/v1/option_snapshots/${encodeURIComponent(selected.symbol)}/premium_trend` +
          `?contract_symbol=${encodeURIComponent(contractSymbol)}`,
      );
      const json = (await res.json()) as PremiumTrendPoint[];
      setTrendData(Array.isArray(json) ? json : []);
    } catch {
      setTrendData([]);
    }
  }

  async function handleAdd(symbol: string) {
    const createRes = await fetch("/api/v1/tracked_tickers", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": csrfToken(),
        "X-Requested-With": "XMLHttpRequest",
      },
      body: JSON.stringify({ symbol }),
    });
    const newTicker = (await createRes.json()) as TrackedTicker & {
      error?: string;
    };
    if (!createRes.ok) throw new Error(newTicker.error ?? "新增失敗");

    setTickers((prev) => {
      const exists = prev.some((t) => t.id === newTicker.id);
      return exists
        ? prev.map((t) => (t.id === newTicker.id ? newTicker : t))
        : [...prev, newTicker].sort((a, b) => a.symbol.localeCompare(b.symbol));
    });
    setSelected(newTicker);
    setSnapshots([]);
    setExpirations([]);
    setSelectedExp("");
    setAvailableDates([]);

    setLoading(true);
    setError(null);
    try {
      const collectRes = await fetch(
        `/api/v1/tracked_tickers/${newTicker.id}/collect`,
        {
          method: "POST",
          headers: {
            "X-CSRF-Token": csrfToken(),
            "X-Requested-With": "XMLHttpRequest",
          },
        },
      );
      if (!collectRes.ok) {
        const err = (await collectRes.json().catch(() => ({}))) as {
          error?: string;
        };
        setError(err.error ?? "資料抓取失敗");
        return;
      }
      await loadSnapshots(newTicker);
    } finally {
      setLoading(false);
    }
  }

  async function handleDelete(id: number) {
    if (!confirm("確定要移除此追蹤代號？所有快照資料也會一併刪除。")) return;
    const res = await fetch(`/api/v1/tracked_tickers/${id}`, {
      method: "DELETE",
      headers: {
        "X-CSRF-Token": csrfToken(),
        "X-Requested-With": "XMLHttpRequest",
      },
    });
    if (!res.ok) return;
    setTickers((prev) => prev.filter((t) => t.id !== id));
    if (selected?.id === id) {
      setSelected(null);
      setSnapshots([]);
    }
  }

  function handleSelect(ticker: TrackedTicker) {
    if (ticker.id === selected?.id) return;
    setSelected(ticker);
    setSnapshots([]);
    setExpirations([]);
    setSelectedExp("");
    setAvailableDates([]);
    loadSnapshots(ticker);
  }

  function handleDateSelect(date: string) {
    if (!selected || date === snapshotDate) return;
    loadSnapshots(selected, date);
  }

  useEffect(() => {
    if (selected) loadSnapshots(selected);
  }, []); // eslint-disable-line react-hooks/exhaustive-deps

  const chainRows = selectedExp
    ? buildChainRows(snapshots, selectedExp, underlyingPrice)
    : [];
  const dte = selectedExp ? calcDte(selectedExp) : null;
  const tradingDays = selectedExp ? calcTradingDays(selectedExp) : null;

  return (
    <div className="flex h-full min-h-screen bg-gray-50 text-gray-800 overflow-hidden">
      <TickerSidebar
        tickers={tickers}
        selected={selected}
        onSelect={handleSelect}
        onAdd={handleAdd}
        onDelete={handleDelete}
      />

      <div className="flex-1 flex flex-col overflow-hidden">
        {!selected ? (
          <div className="flex items-center justify-center h-full text-gray-400 text-sm">
            從左側新增並選擇追蹤代號
          </div>
        ) : (
          <>
            {/* Snapshot date tabs — only shown when multiple dates available */}
            <SnapshotDateTabs
              dates={availableDates}
              selected={snapshotDate ?? ""}
              onSelect={handleDateSelect}
            />

            {/* Expiration tabs */}
            <ExpirationTabs
              expirations={expirations}
              selected={selectedExp}
              onSelect={(exp) => {
                setSelectedExp(exp);
                setSelectedContract(null);
                setTrendData([]);
              }}
            />

            {/* Header */}
            <div className="flex items-center gap-3 px-4 py-2 border-b border-gray-200 bg-white shrink-0">
              <div className="flex items-center gap-1">
                <button
                  onClick={() =>
                    setCallPutFilter((f) => (f === "call" ? "both" : "call"))
                  }
                  className={`px-2.5 py-0.5 rounded text-xs font-semibold transition-colors ${
                    callPutFilter === "call"
                      ? "btn-calls-active"
                      : callPutFilter === "put"
                        ? "btn-filter-muted"
                        : "bg-blue-50 text-blue-600 hover:bg-blue-100"
                  }`}
                >
                  Calls
                </button>
                <button
                  onClick={() =>
                    setCallPutFilter((f) => (f === "put" ? "both" : "put"))
                  }
                  className={`px-2.5 py-0.5 rounded text-xs font-semibold transition-colors ${
                    callPutFilter === "put"
                      ? "btn-puts-active"
                      : callPutFilter === "call"
                        ? "btn-filter-muted"
                        : "bg-rose-50 text-rose-600 hover:bg-rose-100"
                  }`}
                >
                  Puts
                </button>
              </div>
              <span className="font-mono font-bold text-sm text-gray-800">
                {selected.symbol}
              </span>
              {selectedExp && (
                <span className="text-xs text-gray-500">{selectedExp}</span>
              )}
              {dte != null && (
                <span className="text-xs text-amber-600 font-medium">
                  距離到期日還有 {dte} 天
                  {tradingDays != null && (
                    <span className="text-gray-400 font-normal ml-1">
                      （{tradingDays} 交易日）
                    </span>
                  )}
                </span>
              )}

              {loading && (
                <span className="text-xs text-blue-600">載入中…</span>
              )}
              {error && <span className="text-xs text-red-500">{error}</span>}
            </div>

            {/* Main content */}
            <div className="flex-1 overflow-y-auto">
              <div className="p-2">
                <OptionsChainTable
                  rows={chainRows}
                  underlyingPrice={underlyingPrice}
                  filter={callPutFilter}
                  selectedContract={selectedContract}
                  onSelect={loadTrend}
                />
              </div>

              {selectedContract && (
                <div className="mx-2 mb-4 bg-white border border-gray-200 rounded-lg p-4 shadow-sm">
                  <p className="text-xs text-gray-600 font-semibold mb-3">
                    Premium 歷史趨勢
                  </p>
                  <PremiumTrendChart
                    data={trendData}
                    contractSymbol={selectedContract}
                  />
                </div>
              )}
            </div>
          </>
        )}
      </div>
    </div>
  );
}
