import type { OptionSnapshotRow } from "../types";

interface Props {
  snapshots: OptionSnapshotRow[];
  selectedContract: string | null;
  onSelectContract: (contractSymbol: string) => void;
}

function fmt(v: number | null, decimals = 2) {
  if (v == null) return "—";
  return `$${v.toFixed(decimals)}`;
}

function fmtIv(v: number | null) {
  if (v == null) return "—";
  return `${(v * 100).toFixed(1)}%`;
}

function fmtNum(v: number | null) {
  if (v == null) return "—";
  return v.toLocaleString();
}

export default function ContractsTable({
  snapshots,
  selectedContract,
  onSelectContract,
}: Props) {
  if (snapshots.length === 0) {
    return (
      <div className="text-center text-gray-500 text-sm py-8">
        尚無快照資料。請先執行 Python 蒐集器抓取資料。
      </div>
    );
  }

  // Group by snapshot_date desc, show latest date's data
  const latestDate = snapshots.reduce(
    (max, s) => (s.snapshot_date > max ? s.snapshot_date : max),
    "",
  );
  const latest = snapshots.filter((s) => s.snapshot_date === latestDate);

  return (
    <div>
      <p className="text-xs text-gray-400 mb-2">
        最新快照：<span className="text-gray-300">{latestDate}</span>
        <span className="ml-2 text-gray-500">
          （共 {latest.length} 個合約）
        </span>
        <span className="ml-2 text-gray-600">點選行查看 Premium 趨勢</span>
      </p>
      <div className="overflow-x-auto">
        <table className="w-full text-xs">
          <thead>
            <tr className="text-gray-400 border-b border-gray-700">
              <th className="text-left py-1.5 pr-3 font-medium">合約</th>
              <th className="text-right py-1.5 pr-3 font-medium">類型</th>
              <th className="text-right py-1.5 pr-3 font-medium">到期</th>
              <th className="text-right py-1.5 pr-3 font-medium">Strike</th>
              <th className="text-right py-1.5 pr-3 font-medium">Bid</th>
              <th className="text-right py-1.5 pr-3 font-medium">Ask</th>
              <th className="text-right py-1.5 pr-3 font-medium">Last</th>
              <th className="text-right py-1.5 pr-3 font-medium">IV</th>
              <th className="text-right py-1.5 pr-3 font-medium">OI</th>
              <th className="text-right py-1.5 font-medium">Vol</th>
            </tr>
          </thead>
          <tbody>
            {latest.map((s) => (
              <tr
                key={s.id}
                onClick={() => onSelectContract(s.contract_symbol)}
                className={`border-b border-gray-800 cursor-pointer transition-colors ${
                  selectedContract === s.contract_symbol
                    ? "bg-blue-900/40"
                    : "hover:bg-gray-800/60"
                }`}
              >
                <td className="py-1.5 pr-3 font-mono text-gray-300 whitespace-nowrap">
                  {s.contract_symbol}
                  {s.in_the_money && (
                    <span className="ml-1 text-green-400 text-xs">ITM</span>
                  )}
                </td>
                <td
                  className={`text-right py-1.5 pr-3 font-medium ${s.option_type === "put" ? "text-red-400" : "text-green-400"}`}
                >
                  {s.option_type.toUpperCase()}
                </td>
                <td className="text-right py-1.5 pr-3 text-gray-300">
                  {s.expiration}
                </td>
                <td className="text-right py-1.5 pr-3 text-gray-200">
                  {fmt(s.strike)}
                </td>
                <td className="text-right py-1.5 pr-3 text-blue-300">
                  {fmt(s.bid)}
                </td>
                <td className="text-right py-1.5 pr-3 text-green-300">
                  {fmt(s.ask)}
                </td>
                <td className="text-right py-1.5 pr-3 text-yellow-300">
                  {fmt(s.last_price)}
                </td>
                <td className="text-right py-1.5 pr-3 text-purple-300">
                  {fmtIv(s.implied_volatility)}
                </td>
                <td className="text-right py-1.5 pr-3 text-gray-400">
                  {fmtNum(s.open_interest)}
                </td>
                <td className="text-right py-1.5 text-gray-400">
                  {fmtNum(s.volume)}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}
