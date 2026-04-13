import type { OptionSnapshotRow } from "../types";

export interface StrikeRow {
  strike: number;
  call: OptionSnapshotRow | null;
  put: OptionSnapshotRow | null;
}

interface Props {
  rows: StrikeRow[];
  underlyingPrice: number;
  selectedContract: string | null;
  onSelect: (contractSymbol: string) => void;
}

function fmtPrice(v: number | null) {
  if (v == null || v === 0) return <span className="text-gray-300">0.00</span>;
  return <span>{v.toFixed(2)}</span>;
}

function fmtIv(v: number | null) {
  if (v == null || v === 0) return <span className="text-gray-300">—</span>;
  return <span>{(v * 100).toFixed(0)}%</span>;
}

function fmtInt(v: number | null) {
  if (v == null || v === 0) return <span className="text-gray-300">0</span>;
  return <span>{v.toLocaleString()}</span>;
}

export default function OptionsChainTable({
  rows,
  underlyingPrice,
  selectedContract,
  onSelect,
}: Props) {
  if (rows.length === 0) {
    return (
      <div className="text-center text-gray-400 text-sm py-8">
        此到期日無資料
      </div>
    );
  }

  const thBase =
    "px-2 py-1.5 text-xs font-semibold text-teal-100 uppercase tracking-wider text-right";

  return (
    <div className="overflow-x-auto">
      <table className="w-full border-collapse text-xs">
        <thead>
          <tr className="bg-teal-700">
            {/* Calls header */}
            <th
              colSpan={6}
              className="py-1.5 text-center text-white text-xs font-bold border-r border-teal-600"
            >
              CALLS
            </th>
            {/* Strike */}
            <th className="px-3 py-1.5 text-center text-teal-100 text-xs font-bold bg-teal-900">
              行權價格
            </th>
            {/* Puts header */}
            <th
              colSpan={6}
              className="py-1.5 text-center text-white text-xs font-bold border-l border-teal-600"
            >
              PUTS
            </th>
          </tr>
          <tr className="bg-teal-800">
            {/* Call columns */}
            <th className={thBase}>持倉量</th>
            <th className={thBase}>交易量</th>
            <th className={thBase}>IV</th>
            <th className={thBase}>要價</th>
            <th className={thBase}>出價</th>
            <th className={`${thBase} border-r border-teal-600`}>價格</th>
            {/* Strike */}
            <th className="px-3 py-1.5 text-center text-xs font-semibold text-teal-100 bg-teal-900"></th>
            {/* Put columns */}
            <th className={`${thBase} border-l border-teal-600 text-left`}>
              價格
            </th>
            <th className={thBase}>出價</th>
            <th className={thBase}>要價</th>
            <th className={thBase}>IV</th>
            <th className={thBase}>交易量</th>
            <th className={thBase}>持倉量</th>
          </tr>
        </thead>
        <tbody>
          {rows.map(({ strike, call, put }) => {
            const callItm = call?.in_the_money ?? strike < underlyingPrice;
            const putItm = put?.in_the_money ?? strike > underlyingPrice;
            const isAtm =
              Math.abs(strike - underlyingPrice) <= underlyingPrice * 0.01;

            const callSelected = call?.contract_symbol === selectedContract;
            const putSelected = put?.contract_symbol === selectedContract;

            const rowBase =
              "border-b border-gray-100 hover:bg-teal-50 transition-colors";
            // call 選中 → call 側亮藍；put 選中 → put 側亮紅；否則依 ITM 狀態
            const callBg = callSelected
              ? "opt-call-selected"
              : callItm
                ? "opt-call-itm"
                : "bg-white";
            const putBg = putSelected
              ? "opt-put-selected"
              : putItm
                ? "opt-put-itm"
                : "bg-white";
            // 行權價格欄：左半跟隨 call，右半跟隨 put
            const strikeCallBg = callSelected
              ? "opt-call-selected"
              : "bg-teal-700";
            const strikePutBg = putSelected
              ? "opt-put-selected"
              : "bg-teal-700";

            return (
              <tr
                key={strike}
                className={`${rowBase} ${isAtm ? "ring-1 ring-inset ring-amber-500/60" : ""}`}
              >
                {/* Call cells — reversed order (OI, Vol, IV, Ask, Bid, Last) */}
                <td
                  className={`px-2 py-1.5 text-right tabular-nums text-blue-600 ${callBg} cursor-pointer`}
                  onClick={() => call && onSelect(call.contract_symbol)}
                >
                  {fmtInt(call?.open_interest ?? null)}
                </td>
                <td
                  className={`px-2 py-1.5 text-right tabular-nums text-blue-600 ${callBg} cursor-pointer`}
                  onClick={() => call && onSelect(call.contract_symbol)}
                >
                  {fmtInt(call?.volume ?? null)}
                </td>
                <td
                  className={`px-2 py-1.5 text-right tabular-nums text-indigo-600 ${callBg} cursor-pointer`}
                  onClick={() => call && onSelect(call.contract_symbol)}
                >
                  {fmtIv(call?.implied_volatility ?? null)}
                </td>
                <td
                  className={`px-2 py-1.5 text-right tabular-nums text-gray-600 ${callBg} cursor-pointer`}
                  onClick={() => call && onSelect(call.contract_symbol)}
                >
                  {fmtPrice(call?.ask ?? null)}
                </td>
                <td
                  className={`px-2 py-1.5 text-right tabular-nums text-blue-700 ${callBg} cursor-pointer`}
                  onClick={() => call && onSelect(call.contract_symbol)}
                >
                  {fmtPrice(call?.bid ?? null)}
                </td>
                <td
                  className={`px-2 py-1.5 text-right tabular-nums text-gray-800 font-medium border-r border-gray-200 ${callBg} cursor-pointer`}
                  onClick={() => call && onSelect(call.contract_symbol)}
                >
                  {fmtPrice(call?.last_price ?? null)}
                </td>

                {/* Strike — 左半跟 call 同色，右半跟 put 同色 */}
                <td className="py-1.5 text-sm">
                  <div className="flex items-center">
                    <div
                      className={`flex-1 py-1.5 text-right pr-1 font-mono font-semibold text-white tabular-nums select-none ${strikeCallBg}
                        ${call ? "cursor-pointer hover:text-teal-200 transition-colors" : "opacity-40"}`}
                      title={
                        call
                          ? `選 Call ${call.contract_symbol}`
                          : "無 Call 資料"
                      }
                      onClick={() => call && onSelect(call.contract_symbol)}
                    >
                      {strike.toFixed(2)}
                    </div>
                    <div className="w-px h-4 bg-teal-500 shrink-0" />
                    <div
                      className={`flex-1 py-1.5 text-left pl-1 font-mono font-semibold text-white tabular-nums select-none ${strikePutBg}
                        ${put ? "cursor-pointer hover:text-teal-200 transition-colors" : "opacity-40"}`}
                      title={
                        put ? `選 Put ${put.contract_symbol}` : "無 Put 資料"
                      }
                      onClick={() => put && onSelect(put.contract_symbol)}
                    >
                      {strike.toFixed(2)}
                    </div>
                  </div>
                </td>

                {/* Put cells */}
                <td
                  className={`px-2 py-1.5 text-right tabular-nums text-gray-800 font-medium border-l border-gray-200 ${putBg} cursor-pointer`}
                  onClick={() => put && onSelect(put.contract_symbol)}
                >
                  {fmtPrice(put?.last_price ?? null)}
                </td>
                <td
                  className={`px-2 py-1.5 text-right tabular-nums text-blue-700 ${putBg} cursor-pointer`}
                  onClick={() => put && onSelect(put.contract_symbol)}
                >
                  {fmtPrice(put?.bid ?? null)}
                </td>
                <td
                  className={`px-2 py-1.5 text-right tabular-nums text-gray-600 ${putBg} cursor-pointer`}
                  onClick={() => put && onSelect(put.contract_symbol)}
                >
                  {fmtPrice(put?.ask ?? null)}
                </td>
                <td
                  className={`px-2 py-1.5 text-right tabular-nums text-indigo-600 ${putBg} cursor-pointer`}
                  onClick={() => put && onSelect(put.contract_symbol)}
                >
                  {fmtIv(put?.implied_volatility ?? null)}
                </td>
                <td
                  className={`px-2 py-1.5 text-right tabular-nums text-blue-600 ${putBg} cursor-pointer`}
                  onClick={() => put && onSelect(put.contract_symbol)}
                >
                  {fmtInt(put?.volume ?? null)}
                </td>
                <td
                  className={`px-2 py-1.5 text-right tabular-nums text-blue-600 ${putBg} cursor-pointer`}
                  onClick={() => put && onSelect(put.contract_symbol)}
                >
                  {fmtInt(put?.open_interest ?? null)}
                </td>
              </tr>
            );
          })}
        </tbody>
      </table>
    </div>
  );
}
