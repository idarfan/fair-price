import React, { useState } from "react";
import type { TrackedTicker } from "../types";

interface Props {
  tickers: TrackedTicker[];
  selected: TrackedTicker | null;
  onSelect: (ticker: TrackedTicker) => void;
  onAdd: (symbol: string) => Promise<void>;
  onDelete: (id: number) => Promise<void>;
}

export default function TickerSidebar({
  tickers,
  selected,
  onSelect,
  onAdd,
  onDelete,
}: Props) {
  const [input, setInput] = useState("");
  const [adding, setAdding] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [collapsed, setCollapsed] = useState(false);

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

  if (collapsed) {
    return (
      <aside className="w-8 shrink-0 border-r border-gray-200 bg-teal-700 flex flex-col items-center pt-2 gap-2">
        <button
          onClick={() => setCollapsed(false)}
          title="展開清單"
          className="text-teal-100 hover:text-white transition-colors text-sm"
        >
          ▶
        </button>
        {selected && (
          <span
            className="text-[10px] font-mono font-bold text-teal-200 writing-mode-vertical"
            style={{ writingMode: "vertical-rl", textOrientation: "mixed" }}
          >
            {selected.symbol}
          </span>
        )}
      </aside>
    );
  }

  return (
    <aside className="w-52 shrink-0 border-r border-gray-200 bg-white flex flex-col">
      <div className="px-3 py-3 border-b border-gray-200 bg-teal-700">
        <div className="flex items-center justify-between mb-2">
          <p className="text-xs text-teal-100 font-semibold uppercase tracking-wider">
            追蹤清單
          </p>
          <button
            onClick={() => setCollapsed(true)}
            title="收摺清單"
            className="text-teal-300 hover:text-white transition-colors text-xs leading-none"
          >
            ◀
          </button>
        </div>
        <form onSubmit={handleAdd} className="flex gap-1">
          <input
            type="text"
            value={input}
            onChange={(e) => setInput(e.target.value.toUpperCase())}
            placeholder="代號 e.g. NOK"
            maxLength={10}
            className="flex-1 min-w-0 bg-white border border-teal-500 rounded px-2 py-1 text-xs text-gray-800 placeholder-gray-400 focus:outline-none focus:border-teal-300"
          />
          <button
            type="submit"
            disabled={adding || !input.trim()}
            className="px-2 py-1 text-xs bg-orange-500 hover:bg-orange-400 disabled:opacity-40 rounded text-white transition-colors"
          >
            {adding ? "…" : "+"}
          </button>
        </form>
        {error && <p className="text-xs text-red-300 mt-1">{error}</p>}
      </div>

      <div className="flex-1 overflow-y-auto py-1">
        {tickers.length === 0 && (
          <p className="text-xs text-gray-400 text-center py-6">尚無追蹤代號</p>
        )}
        {tickers.map((ticker) => (
          <div
            key={ticker.id}
            onClick={() => onSelect(ticker)}
            className={`group flex items-center gap-2 px-3 py-2 cursor-pointer transition-colors ${
              selected?.id === ticker.id
                ? "bg-teal-50 border-r-2 border-teal-600"
                : "hover:bg-gray-50"
            }`}
          >
            <div className="flex-1 min-w-0">
              <div className="flex items-center gap-1.5">
                <span className="text-sm font-mono font-medium text-gray-800">
                  {ticker.symbol}
                </span>
              </div>
              {ticker.last_snapshot_date && (
                <p className="text-xs text-gray-400 truncate">
                  {ticker.last_snapshot_date}
                </p>
              )}
            </div>
            <button
              onClick={(e) => {
                e.stopPropagation();
                onDelete(ticker.id);
              }}
              title="移除"
              className="opacity-0 group-hover:opacity-100 p-0.5 rounded text-gray-400 hover:text-red-500 transition-colors"
            >
              ✕
            </button>
          </div>
        ))}
      </div>
    </aside>
  );
}
