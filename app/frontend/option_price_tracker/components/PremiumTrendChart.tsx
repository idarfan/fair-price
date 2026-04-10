import {
  CartesianGrid,
  Legend,
  Line,
  LineChart,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts";
import type { PremiumTrendPoint } from "../types";

interface Props {
  data: PremiumTrendPoint[];
  contractSymbol: string;
}

/** Returns true if all points are from the same calendar date (intraday). */
function isIntraday(data: PremiumTrendPoint[]): boolean {
  if (data.length < 2) return false;
  const first = data[0];
  if (!first) return false;
  const firstDate = first.snapped_at.slice(0, 10); // "YYYY-MM-DD"
  return data.every((d) => d.snapped_at.slice(0, 10) === firstDate);
}

function fmtXAxis(snapped_at: string, intraday: boolean): string {
  const d = new Date(snapped_at);
  if (intraday) {
    // Convert UTC → US Eastern (ET) for display
    return d.toLocaleTimeString("en-US", {
      timeZone: "America/New_York",
      hour: "2-digit",
      minute: "2-digit",
      hour12: false,
    });
  }
  return d.toLocaleDateString("en-US", { month: "short", day: "numeric" });
}

export default function PremiumTrendChart({ data, contractSymbol }: Props) {
  if (data.length === 0) {
    return (
      <div className="flex items-center justify-center h-48 text-gray-500 text-sm">
        點選下方合約查看 Premium 趨勢
      </div>
    );
  }

  const intraday = isIntraday(data);

  const chartData = data.map((d) => ({
    label: fmtXAxis(d.snapped_at, intraday),
    bid: d.bid,
    ask: d.ask,
    last: d.last_price,
    iv:
      d.implied_volatility != null
        ? +(d.implied_volatility * 100).toFixed(1)
        : null,
  }));

  return (
    <div>
      <div className="flex items-center gap-3 mb-2">
        <p className="text-xs text-gray-400 font-mono">{contractSymbol}</p>
        {intraday && (
          <span className="text-xs text-yellow-400 bg-yellow-900/30 px-1.5 py-0.5 rounded">
            盤中 (ET)
          </span>
        )}
      </div>
      <ResponsiveContainer width="100%" height={220}>
        <LineChart
          data={chartData}
          margin={{ top: 4, right: 40, left: 0, bottom: 0 }}
        >
          <CartesianGrid strokeDasharray="3 3" stroke="#374151" />
          <XAxis
            dataKey="label"
            tick={{ fontSize: 10, fill: "#9ca3af" }}
            tickLine={false}
            axisLine={false}
            interval="preserveStartEnd"
          />
          <YAxis
            yAxisId="price"
            tick={{ fontSize: 10, fill: "#9ca3af" }}
            tickLine={false}
            axisLine={false}
            tickFormatter={(v: number) => `$${v.toFixed(2)}`}
          />
          <YAxis
            yAxisId="iv"
            orientation="right"
            tick={{ fontSize: 10, fill: "#a78bfa" }}
            tickLine={false}
            axisLine={false}
            tickFormatter={(v: number) => `${v}%`}
          />
          <Tooltip
            contentStyle={{
              backgroundColor: "#1f2937",
              border: "1px solid #374151",
              fontSize: 11,
            }}
            formatter={(value, name) => {
              if (typeof value !== "number")
                return [String(value ?? "—"), String(name)];
              if (name === "iv") return [`${value}%`, "IV"];
              return [`$${value.toFixed(2)}`, String(name)];
            }}
          />
          <Legend wrapperStyle={{ fontSize: 11 }} />
          <Line
            yAxisId="price"
            type="monotone"
            dataKey="bid"
            name="出價"
            stroke="#60a5fa"
            dot={false}
            strokeWidth={1.5}
          />
          <Line
            yAxisId="price"
            type="monotone"
            dataKey="ask"
            name="要價"
            stroke="#34d399"
            dot={false}
            strokeWidth={1.5}
          />
          <Line
            yAxisId="price"
            type="monotone"
            dataKey="last"
            stroke="#fbbf24"
            dot={false}
            strokeWidth={1.5}
          />
          <Line
            yAxisId="iv"
            type="monotone"
            dataKey="iv"
            stroke="#a78bfa"
            dot={false}
            strokeWidth={1}
            strokeDasharray="4 2"
          />
        </LineChart>
      </ResponsiveContainer>
    </div>
  );
}
