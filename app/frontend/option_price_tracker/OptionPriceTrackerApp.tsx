import { useCallback, useEffect, useState } from "react";
import TickerSidebar from "./components/TickerSidebar";
import FilterBar from "./components/FilterBar";
import PremiumTrendChart from "./components/PremiumTrendChart";
import ContractsTable from "./components/ContractsTable";
import type {
  TrackedTicker,
  OptionSnapshotRow,
  PremiumTrendPoint,
  OptionType,
} from "./types";

function csrfToken(): string {
  return (
    (document.querySelector('meta[name="csrf-token"]') as HTMLMetaElement)
      ?.content ?? ""
  );
}

interface Props {
  initialTickers: TrackedTicker[];
}

export default function OptionPriceTrackerApp({ initialTickers }: Props) {
  const [tickers, setTickers] = useState<TrackedTicker[]>(initialTickers);
  const [selected, setSelected] = useState<TrackedTicker | null>(
    initialTickers[0] ?? null,
  );

  const [optionType, setOptionType] = useState<OptionType>("put");
  const [expiration, setExpiration] = useState("");
  const [days, setDays] = useState(60);
  const [expirations, setExpirations] = useState<string[]>([]);

  const [snapshots, setSnapshots] = useState<OptionSnapshotRow[]>([]);
  const [selectedContract, setSelectedContract] = useState<string | null>(null);
  const [trendData, setTrendData] = useState<PremiumTrendPoint[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Load snapshots for selected ticker
  const loadSnapshots = useCallback(
    async (ticker: TrackedTicker, type: OptionType, exp: string, d: number) => {
      setLoading(true);
      setError(null);
      setSelectedContract(null);
      setTrendData([]);
      try {
        const params = new URLSearchParams({ days: String(d) });
        if (type !== "all") params.set("type", type);
        if (exp) params.set("expiration", exp);
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
        };
        setSnapshots(json.snapshots);
        setExpirations(json.expirations);
      } catch {
        setError("網路錯誤，請稍後再試");
      } finally {
        setLoading(false);
      }
    },
    [],
  );

  // Load premium trend for a specific contract
  async function loadTrend(contractSymbol: string) {
    if (!selected) return;
    setSelectedContract(contractSymbol);
    try {
      const res = await fetch(
        `/api/v1/option_snapshots/${encodeURIComponent(selected.symbol)}/premium_trend?contract_symbol=${encodeURIComponent(contractSymbol)}`,
      );
      const json = (await res.json()) as PremiumTrendPoint[];
      setTrendData(Array.isArray(json) ? json : []);
    } catch {
      setTrendData([]);
    }
  }

  // API: add ticker
  async function handleAdd(symbol: string) {
    const res = await fetch("/api/v1/tracked_tickers", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": csrfToken(),
        "X-Requested-With": "XMLHttpRequest",
      },
      body: JSON.stringify({ symbol }),
    });
    const json = (await res.json()) as TrackedTicker & { error?: string };
    if (!res.ok) throw new Error(json.error ?? "新增失敗");
    setTickers((prev) => {
      const exists = prev.some((t) => t.id === json.id);
      return exists
        ? prev.map((t) => (t.id === json.id ? json : t))
        : [...prev, json].sort((a, b) => a.symbol.localeCompare(b.symbol));
    });
  }

  // API: delete ticker
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

  // API: toggle active
  async function handleToggle(ticker: TrackedTicker) {
    const res = await fetch(`/api/v1/tracked_tickers/${ticker.id}`, {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": csrfToken(),
        "X-Requested-With": "XMLHttpRequest",
      },
      body: JSON.stringify({ active: !ticker.active }),
    });
    const json = (await res.json()) as TrackedTicker;
    if (!res.ok) return;
    setTickers((prev) => prev.map((t) => (t.id === json.id ? json : t)));
    if (selected?.id === json.id) setSelected(json);
  }

  function handleSelect(ticker: TrackedTicker) {
    if (ticker.id === selected?.id) return;
    setSelected(ticker);
    setExpiration("");
    loadSnapshots(ticker, optionType, "", days);
  }

  function handleOptionTypeChange(t: OptionType) {
    setOptionType(t);
    if (selected) loadSnapshots(selected, t, expiration, days);
  }

  function handleExpirationChange(exp: string) {
    setExpiration(exp);
    if (selected) loadSnapshots(selected, optionType, exp, days);
  }

  function handleDaysChange(d: number) {
    setDays(d);
    if (selected) loadSnapshots(selected, optionType, expiration, d);
  }

  useEffect(() => {
    if (selected) loadSnapshots(selected, optionType, expiration, days);
  }, []); // eslint-disable-line react-hooks/exhaustive-deps

  return (
    <div className="flex h-full min-h-screen bg-gray-900 text-white overflow-hidden">
      <TickerSidebar
        tickers={tickers}
        selected={selected}
        onSelect={handleSelect}
        onAdd={handleAdd}
        onDelete={handleDelete}
        onToggle={handleToggle}
      />

      <div className="flex-1 flex flex-col overflow-hidden">
        {!selected ? (
          <div className="flex items-center justify-center h-full text-gray-500 text-sm">
            從左側新增並選擇追蹤代號
          </div>
        ) : (
          <>
            {/* Header */}
            <div className="flex items-center gap-3 px-4 py-3 border-b border-gray-700">
              <h2 className="text-base font-semibold font-mono">
                {selected.symbol}
              </h2>
              <span className="text-xs text-gray-400">期權歷史價格追蹤</span>
              {loading && (
                <span className="text-xs text-blue-400 ml-auto">載入中…</span>
              )}
              {error && (
                <span className="text-xs text-red-400 ml-auto">{error}</span>
              )}
            </div>

            <FilterBar
              optionType={optionType}
              expiration={expiration}
              expirations={expirations}
              days={days}
              onOptionTypeChange={handleOptionTypeChange}
              onExpirationChange={handleExpirationChange}
              onDaysChange={handleDaysChange}
            />

            <div className="flex-1 overflow-y-auto p-4 flex flex-col gap-4">
              {/* Premium Trend Chart */}
              <div className="bg-gray-800 rounded-lg p-4">
                <p className="text-xs text-gray-400 font-semibold mb-3">
                  Premium 趨勢圖
                </p>
                <PremiumTrendChart
                  data={trendData}
                  contractSymbol={selectedContract ?? ""}
                />
              </div>

              {/* Contracts Table */}
              <div className="bg-gray-800 rounded-lg p-4">
                <p className="text-xs text-gray-400 font-semibold mb-3">
                  合約快照列表
                </p>
                <ContractsTable
                  snapshots={snapshots}
                  selectedContract={selectedContract}
                  onSelectContract={loadTrend}
                />
              </div>
            </div>
          </>
        )}
      </div>
    </div>
  );
}
