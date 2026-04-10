import React, { useState } from "react";
import type { TrackedTicker } from "../types";

interface Props {
  tickers: TrackedTicker[];
  selected: TrackedTicker | null;
  onSelect: (ticker: TrackedTicker) => void;
  onAdd: (symbol: string) => Promise<void>;
  onDelete: (id: number) => Promise<void>;
  onToggle: (ticker: TrackedTicker) => Promise<void>;
}

export default function TickerSidebar({
  tickers,
  selected,
  onSelect,
  onAdd,
  onDelete,
  onToggle,
}: Props) {
  const [input, setInput] = useState("");
  const [adding, setAdding] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function handleAdd(e: React.SyntheticEvent<HTMLFormElement>) {
    e.preventDefault();
    const sym = input.trim().toUpperCase();
    if (!sym) return;
    setAdding(true);
    setError(null);
    try {
      await onAdd(sym);
      setInput("");
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : "新增失敗");
    } finally {
      setAdding(false);
    }
  }

  return (
    <aside className="w-52 shrink-0 border-r border-gray-700 flex flex-col">
      <div className="px-3 py-3 border-b border-gray-700">
        <p className="text-xs text-gray-400 font-semibold uppercase tracking-wider mb-2">
          追蹤清單
        </p>
        <form onSubmit={handleAdd} className="flex gap-1">
          <input
            type="text"
            value={input}
            onChange={(e) => setInput(e.target.value.toUpperCase())}
            placeholder="代號 e.g. NOK"
            maxLength={10}
            className="flex-1 min-w-0 bg-gray-800 border border-gray-600 rounded px-2 py-1 text-xs text-white placeholder-gray-500 focus:outline-none focus:border-blue-500"
          />
          <button
            type="submit"
            disabled={adding || !input.trim()}
            className="px-2 py-1 text-xs bg-blue-600 hover:bg-blue-500 disabled:opacity-40 rounded text-white transition-colors"
          >
            {adding ? "…" : "+"}
          </button>
        </form>
        {error && <p className="text-xs text-red-400 mt-1">{error}</p>}
      </div>

      <div className="flex-1 overflow-y-auto py-1">
        {tickers.length === 0 && (
          <p className="text-xs text-gray-500 text-center py-6">尚無追蹤代號</p>
        )}
        {tickers.map((ticker) => (
          <div
            key={ticker.id}
            onClick={() => onSelect(ticker)}
            className={`group flex items-center gap-2 px-3 py-2 cursor-pointer transition-colors ${
              selected?.id === ticker.id
                ? "bg-blue-900/50 border-r-2 border-blue-500"
                : "hover:bg-gray-800"
            }`}
          >
            <div className="flex-1 min-w-0">
              <div className="flex items-center gap-1.5">
                <span
                  className={`text-sm font-mono font-medium ${ticker.active ? "text-white" : "text-gray-500"}`}
                >
                  {ticker.symbol}
                </span>
                {!ticker.active && (
                  <span className="text-xs text-gray-600">暫停</span>
                )}
              </div>
              {ticker.last_snapshot_date && (
                <p className="text-xs text-gray-500 truncate">
                  {ticker.last_snapshot_date}
                </p>
              )}
            </div>
            <div className="flex items-center gap-1 opacity-0 group-hover:opacity-100 transition-opacity">
              <button
                onClick={(e) => {
                  e.stopPropagation();
                  onToggle(ticker);
                }}
                title={ticker.active ? "暫停追蹤" : "恢復追蹤"}
                className="p-0.5 rounded text-gray-400 hover:text-yellow-400 transition-colors"
              >
                {ticker.active ? "⏸" : "▶"}
              </button>
              <button
                onClick={(e) => {
                  e.stopPropagation();
                  onDelete(ticker.id);
                }}
                title="移除"
                className="p-0.5 rounded text-gray-400 hover:text-red-400 transition-colors"
              >
                ✕
              </button>
            </div>
          </div>
        ))}
      </div>
    </aside>
  );
}
