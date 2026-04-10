import { useCallback, useEffect, useState } from "react";
import TickerSidebar from "./components/TickerSidebar";
import ExpirationTabs from "./components/ExpirationTabs";
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

function buildChainRows(
  snapshots: OptionSnapshotRow[],
  expiration: string,
): StrikeRow[] {
  const filtered = snapshots.filter((s) => s.expiration === expiration);
  const strikes = [...new Set(filtered.map((s) => s.strike))].sort(
    (a, b) => a - b,
  );
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
  const [underlyingPrice, setUnderlyingPrice] = useState(0);

  const [selectedContract, setSelectedContract] = useState<string | null>(null);
  const [trendData, setTrendData] = useState<PremiumTrendPoint[]>([]);

  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const loadSnapshots = useCallback(async (ticker: TrackedTicker) => {
    setLoading(true);
    setError(null);
    setSelectedContract(null);
    setTrendData([]);
    try {
      const res = await fetch(
        `/api/v1/option_snapshots/${encodeURIComponent(ticker.symbol)}?latest_only=true`,
      );
      if (!res.ok) {
        const json = (await res.json().catch(() => ({}))) as { error?: string };
        setError(json.error ?? "載入失敗");
        return;
      }
      const json = (await res.json()) as {
        snapshots: OptionSnapshotRow[];
        expirations: string[];
        latest_snapshot_date: string | null;
      };
      setSnapshots(json.snapshots);
      setExpirations(json.expirations);
      setSnapshotDate(json.latest_snapshot_date);
      setSelectedExp(json.expirations[0] ?? "");
      const price = json.snapshots[0]?.underlying_price ?? 0;
      setUnderlyingPrice(price);
    } catch {
      setError("網路錯誤，請稍後再試");
    } finally {
      setLoading(false);
    }
  }, []);

  async function loadTrend(contractSymbol: string) {
    if (!selected) return;
    setSelectedContract(contractSymbol);
    try {
      const res = await fetch(
        `/api/v1/option_snapshots/${encodeURIComponent(selected.symbol)}/premium_trend` +
          `?contract_symbol=${encodeURIComponent(contractSymbol)}&hours=36`,
      );
      const json = (await res.json()) as PremiumTrendPoint[];
      setTrendData(Array.isArray(json) ? json : []);
    } catch {
      setTrendData([]);
    }
  }

  async function handleAdd(symbol: string) {
    // 1. 建立追蹤代號
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

    // 2. 加入清單並立即選取
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

    // 3. 自動抓取期權資料（呼叫 Python collector）
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
      // 4. 抓完自動載入期權鏈
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
    setSnapshots([]);
    setExpirations([]);
    setSelectedExp("");
    loadSnapshots(ticker);
  }

  useEffect(() => {
    if (selected) loadSnapshots(selected);
  }, []); // eslint-disable-line react-hooks/exhaustive-deps

  const chainRows = selectedExp ? buildChainRows(snapshots, selectedExp) : [];
  const dte = selectedExp ? calcDte(selectedExp) : null;

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
            <div className="flex items-center gap-3 px-4 py-2 border-b border-gray-700 shrink-0">
              <span className="text-xs text-gray-400 font-medium">
                Calls / Puts
              </span>
              <span className="font-mono font-bold text-sm">
                {selected.symbol}
              </span>
              {selectedExp && (
                <span className="text-xs text-gray-300">{selectedExp}</span>
              )}
              {dte != null && (
                <span className="text-xs text-yellow-400">
                  距離到期日還有 {dte} 天
                </span>
              )}
              {underlyingPrice > 0 && (
                <span className="text-xs text-gray-500 ml-auto">
                  現價 ${underlyingPrice.toFixed(2)}
                </span>
              )}
              {snapshotDate && (
                <span className="text-xs text-gray-600">
                  快照 {snapshotDate}
                </span>
              )}
              {loading && (
                <span className="text-xs text-blue-400">載入中…</span>
              )}
              {error && <span className="text-xs text-red-400">{error}</span>}
            </div>

            {/* Main content */}
            <div className="flex-1 overflow-y-auto">
              {/* Chain table */}
              <div className="p-2">
                <OptionsChainTable
                  rows={chainRows}
                  underlyingPrice={underlyingPrice}
                  selectedContract={selectedContract}
                  onSelect={loadTrend}
                />
              </div>

              {/* Premium trend chart — appears when a contract is selected */}
              {selectedContract && (
                <div className="mx-2 mb-4 bg-gray-800 rounded-lg p-4">
                  <p className="text-xs text-gray-400 font-semibold mb-3">
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
