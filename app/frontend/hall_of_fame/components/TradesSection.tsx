import React, { useState } from "react";
import type { TradeRow, TradeShare, Trades } from "../types";
import {
  DASH,
  OWNER_LABELS,
  RIGHT_LABELS,
  TX_TYPE_LABELS,
  fmtPct,
  fmtAmount,
} from "../format";
import ReviewBadge from "./ReviewBadge";

type Filter = "all" | "buy" | "sell";

const FILTERS: { key: Filter; label: string }[] = [
  { key: "all", label: "全部" },
  { key: "buy", label: "買" },
  { key: "sell", label: "賣" },
];

function matches(row: TradeRow, filter: Filter): boolean {
  if (filter === "buy") return row.tx_type === "P";
  if (filter === "sell")
    return row.tx_type === "S" || row.tx_type === "S_partial";
  return true;
}

function OptionCells({ row }: { row: TradeRow }) {
  const o = row.option;
  if (!o)
    return (
      <td className="whitespace-nowrap px-2 py-1 text-gray-400" colSpan={7}>
        {DASH}
      </td>
    );
  return (
    <>
      <td className="whitespace-nowrap px-2 py-1">
        {o.right ? (RIGHT_LABELS[o.right] ?? o.right) : DASH}
      </td>
      <td className="whitespace-nowrap px-2 py-1 text-right">
        {o.strike === null ? DASH : `$${o.strike}`}
      </td>
      <td className="whitespace-nowrap px-2 py-1">{o.expiration ?? DASH}</td>
      <td className="whitespace-nowrap px-2 py-1 text-right">
        {fmtAmount(row.amount_label, row.amount_min, row.amount_max)}
      </td>
      <td className="whitespace-nowrap px-2 py-1" title={o.calc_note ?? ""}>
        {o.contracts ?? DASH}
      </td>
      <td className="whitespace-nowrap px-2 py-1" title={o.calc_note ?? ""}>
        {o.premium ?? DASH}
      </td>
      <td
        className="whitespace-nowrap px-2 py-1"
        title={o.calc_note ?? ""}
        data-testid="option-source"
      >
        {o.source_label ?? DASH}
      </td>
    </>
  );
}

function SharesTable({
  title,
  shares,
}: {
  title: string;
  shares: TradeShare[];
}) {
  return (
    <div className="lg:flex-1">
      <h4 className="mb-1 text-xs font-semibold text-gray-700">{title}</h4>
      {shares.length === 0 ? (
        <p className="text-xs text-gray-400">無</p>
      ) : (
        <table className="min-w-full text-xs">
          <thead className="bg-gray-50 text-gray-600">
            <tr>
              <th className="px-2 py-1 text-left">Ticker／資產</th>
              <th className="px-2 py-1 text-right">筆數</th>
              <th className="px-2 py-1 text-right">估算佔比</th>
            </tr>
          </thead>
          <tbody>
            {shares.map((s) => (
              <tr key={s.key} className="border-t border-gray-100">
                <td className="whitespace-nowrap px-2 py-1">{s.key}</td>
                <td className="whitespace-nowrap px-2 py-1 text-right">
                  {s.count}
                </td>
                <td className="whitespace-nowrap px-2 py-1 text-right">
                  {s.unbounded ? "≥ " : ""}
                  {fmtPct(s.estimated)}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
    </div>
  );
}

export default function TradesSection({ trades }: { trades: Trades }) {
  const [filter, setFilter] = useState<Filter>("all");
  const rows = trades.rows.filter((r) => matches(r, filter));

  return (
    <section className="space-y-3">
      <div className="flex flex-wrap items-center gap-3">
        <h3 className="text-base font-semibold text-gray-900">
          交易（近 12 個月 PTR）
        </h3>
        <span className="text-xs text-gray-500">
          {trades.since ? `${trades.since} 起` : ""}
        </span>
        <div
          className="ml-auto flex gap-1"
          role="tablist"
          aria-label="買賣篩選"
        >
          {FILTERS.map((f) => (
            <button
              key={f.key}
              type="button"
              role="tab"
              aria-selected={filter === f.key}
              onClick={() => setFilter(f.key)}
              className={`rounded px-2 py-1 text-xs ${filter === f.key ? "bg-blue-600 text-white" : "bg-gray-100 text-gray-700"}`}
            >
              {f.label}
            </button>
          ))}
        </div>
      </div>
      <div className="overflow-x-auto">
        <table className="min-w-full text-xs" data-testid="trades-table">
          <thead className="bg-gray-50 text-gray-600">
            <tr>
              {[
                "日期",
                "資產",
                "Ticker",
                "持有人",
                "買/賣",
                "區間",
                "申報日",
                "Call/Put",
                "履約價",
                "到期日",
                "買入金額區間",
                "口數",
                "每股權利金",
                "資料來源",
                "原始 PDF",
              ].map((h) => (
                <th key={h} className="whitespace-nowrap px-2 py-1 text-left">
                  {h}
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {rows.map((r) => (
              <tr
                key={r.id}
                className="border-t border-gray-100"
                data-testid="trade-row"
              >
                <td className="whitespace-nowrap px-2 py-1">
                  {r.tx_date ?? DASH}
                </td>
                <td className="min-w-48 px-2 py-1">
                  {r.asset_name || DASH}
                  {r.needs_review && (
                    <span className="ml-1">
                      <ReviewBadge note={null} />
                    </span>
                  )}
                  {r.excluded_reason && (
                    <span className="ml-1 text-amber-700">
                      （不列入佔比：{r.excluded_reason}）
                    </span>
                  )}
                </td>
                <td className="whitespace-nowrap px-2 py-1">
                  {r.ticker ?? DASH}
                </td>
                <td className="whitespace-nowrap px-2 py-1">
                  {OWNER_LABELS[r.owner] ?? r.owner}
                </td>
                <td className="whitespace-nowrap px-2 py-1">
                  {r.tx_type ? (TX_TYPE_LABELS[r.tx_type] ?? r.tx_type) : DASH}
                </td>
                <td
                  className="whitespace-nowrap px-2 py-1 text-right"
                  title={r.amount_label ?? ""}
                >
                  {fmtAmount(r.amount_label, r.amount_min, r.amount_max)}
                </td>
                <td className="whitespace-nowrap px-2 py-1">
                  {r.notified_date ?? DASH}
                </td>
                <OptionCells row={r} />
                <td className="whitespace-nowrap px-2 py-1">
                  {r.pdf_url ? (
                    <a
                      className="text-blue-600 underline"
                      href={r.pdf_url}
                      target="_blank"
                      rel="noreferrer"
                    >
                      原始 PDF
                    </a>
                  ) : (
                    DASH
                  )}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      <div className="flex flex-col gap-4 lg:flex-row">
        <SharesTable
          title="買進佔比（依 ticker 加總，估算）"
          shares={trades.shares.purchase}
        />
        <SharesTable
          title="賣出佔比（依 ticker 加總，估算）"
          shares={trades.shares.sale}
        />
      </div>
    </section>
  );
}
