import React, { useState } from "react";
import { Cell, Pie, PieChart, Tooltip } from "recharts";
import type { Holdings, HoldingRow } from "../types";
import { DASH, OWNER_LABELS, fmtAmount, fmtPct } from "../format";
import ReviewBadge from "./ReviewBadge";

type ViewKey = "all" | "securities";

const PIE_COLORS = [
  "#2563eb",
  "#16a34a",
  "#f59e0b",
  "#dc2626",
  "#7c3aed",
  "#0891b2",
  "#db2777",
  "#65a30d",
  "#ea580c",
  "#475569",
  "#9ca3af",
];

/** 圓餅圖：估算佔比前 10 名＋其他。 */
export function pieSlices(
  rows: HoldingRow[],
): { name: string; value: number }[] {
  const ranked = rows.filter((r) => r.estimated !== null && r.estimated > 0);
  const top = ranked
    .slice(0, 10)
    .map((r) => ({ name: r.ticker ?? r.asset_name, value: r.estimated ?? 0 }));
  const rest = ranked.slice(10).reduce((sum, r) => sum + (r.estimated ?? 0), 0);
  return rest > 0 ? [...top, { name: "其他", value: rest }] : top;
}

export default function HoldingsSection({
  holdings,
}: {
  holdings: Holdings | null;
}) {
  const [view, setView] = useState<ViewKey>("all");
  if (!holdings)
    return <p className="text-sm text-gray-500">尚無可用的年報資料。</p>;

  const data = holdings.views[view];
  const upperUnavailable = data.upper_note !== null;

  return (
    <section className="space-y-3">
      <div className="flex flex-wrap items-center gap-3">
        <h3 className="text-base font-semibold text-gray-900">持股（年報）</h3>
        <span className="text-xs text-gray-500" data-testid="holdings-as-of">
          資產截至 {holdings.as_of ?? DASH}
        </span>
        {holdings.parse_status === "needs_review" && (
          <ReviewBadge note={holdings.parse_error} />
        )}
        {holdings.pdf_url && (
          <a
            className="text-xs text-blue-600 underline"
            href={holdings.pdf_url}
            target="_blank"
            rel="noreferrer"
          >
            原始 PDF（{holdings.doc_id}）
          </a>
        )}
        <div
          className="ml-auto flex gap-1"
          role="tablist"
          aria-label="持股範圍"
        >
          {(["all", "securities"] as const).map((key) => (
            <button
              key={key}
              type="button"
              role="tab"
              aria-selected={view === key}
              onClick={() => setView(key)}
              className={`rounded px-2 py-1 text-xs ${view === key ? "bg-blue-600 text-white" : "bg-gray-100 text-gray-700"}`}
            >
              {key === "all" ? "全部資產" : "僅有價證券"}
            </button>
          ))}
        </div>
      </div>
      {data.excluded_count > 0 && (
        <p className="text-xs text-amber-700">
          {data.excluded_count} 列金額或欄位無法對照，照原值列出，不列入佔比。
        </p>
      )}
      {upperUnavailable && (
        <p className="text-xs text-gray-500">
          上限佔比「—」：{data.upper_note}
        </p>
      )}
      <div className="flex flex-col gap-4 lg:flex-row">
        <div className="overflow-x-auto lg:flex-1">
          <table className="min-w-full text-xs" data-testid="holdings-table">
            <thead className="bg-gray-50 text-gray-600">
              <tr>
                <th className="whitespace-nowrap px-2 py-1 text-left">資產</th>
                <th className="whitespace-nowrap px-2 py-1 text-left">
                  Ticker
                </th>
                <th className="whitespace-nowrap px-2 py-1 text-left">
                  持有人
                </th>
                <th className="whitespace-nowrap px-2 py-1 text-right">
                  申報區間
                </th>
                <th className="whitespace-nowrap px-2 py-1 text-right">
                  估算佔比
                </th>
                <th className="whitespace-nowrap px-2 py-1 text-right">
                  下限佔比（估算）
                </th>
                <th className="whitespace-nowrap px-2 py-1 text-right">
                  上限佔比（估算）
                </th>
              </tr>
            </thead>
            <tbody>
              {data.rows.map((r) => (
                <tr
                  key={r.id}
                  className="border-t border-gray-100"
                  data-testid="holding-row"
                >
                  <td className="px-2 py-1">
                    {r.asset_name || DASH}
                    {r.excluded_reason && (
                      <span className="ml-1 text-amber-700">
                        （不列入佔比：{r.excluded_reason}）
                      </span>
                    )}
                  </td>
                  <td className="px-2 py-1">{r.ticker ?? DASH}</td>
                  <td className="whitespace-nowrap px-2 py-1">
                    {OWNER_LABELS[r.owner] ?? r.owner}
                  </td>
                  <td
                    className="px-2 py-1 text-right"
                    title={r.value_label ?? ""}
                  >
                    {fmtAmount(r.value_label, r.value_min, r.value_max)}
                  </td>
                  <td className="px-2 py-1 text-right">
                    {r.unbounded && r.estimated !== null ? "≥ " : ""}
                    {fmtPct(r.estimated)}
                  </td>
                  <td className="px-2 py-1 text-right">{fmtPct(r.lower)}</td>
                  <td className="px-2 py-1 text-right">
                    {upperUnavailable ? DASH : fmtPct(r.upper)}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
        <PieChart width={280} height={280}>
          <Pie
            data={pieSlices(data.rows)}
            dataKey="value"
            nameKey="name"
            outerRadius={110}
            isAnimationActive={false}
          >
            {pieSlices(data.rows).map((s, i) => (
              <Cell key={s.name} fill={PIE_COLORS[i % PIE_COLORS.length]} />
            ))}
          </Pie>
          <Tooltip
            formatter={(v) =>
              typeof v === "number" ? `${v.toFixed(2)}%` : String(v)
            }
          />
        </PieChart>
      </div>
    </section>
  );
}
