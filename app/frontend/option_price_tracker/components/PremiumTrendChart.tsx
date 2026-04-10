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

export default function PremiumTrendChart({ data, contractSymbol }: Props) {
  if (data.length === 0) {
    return (
      <div className="flex items-center justify-center h-48 text-gray-500 text-sm">
        點選下方合約查看 Premium 趨勢
      </div>
    );
  }

  const chartData = data.map((d) => ({
    date: d.date,
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
      <p className="text-xs text-gray-400 mb-2 font-mono">{contractSymbol}</p>
      <ResponsiveContainer width="100%" height={220}>
        <LineChart
          data={chartData}
          margin={{ top: 4, right: 40, left: 0, bottom: 0 }}
        >
          <CartesianGrid strokeDasharray="3 3" stroke="#374151" />
          <XAxis
            dataKey="date"
            tick={{ fontSize: 10, fill: "#9ca3af" }}
            tickLine={false}
            axisLine={false}
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
            stroke="#60a5fa"
            dot={false}
            strokeWidth={1.5}
          />
          <Line
            yAxisId="price"
            type="monotone"
            dataKey="ask"
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
