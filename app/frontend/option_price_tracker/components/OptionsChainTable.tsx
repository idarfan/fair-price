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
  filter?: "both" | "call" | "put";
}

function fmtPrice(v: number | null) {
  if (v == null || v === 0) return <span className="text-gray-300">—</span>;
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
  filter = "both",
}: Props) {
  if (rows.length === 0) {
    return (
      <div className="text-center text-gray-400 text-sm py-8">
        此到期日無資料
      </div>
    );
  }

  const showCalls = filter !== "put";
  const showPuts = filter !== "call";

  const thBase =
    "px-2 py-1.5 text-xs font-medium text-gray-500 uppercase tracking-wider text-right";

  return (
    <div className="overflow-x-auto">
      <table className="w-full border-collapse text-xs">
        <thead>
          <tr className="bg-gray-50 border-b border-gray-200">
            {showCalls && (
              <th
                colSpan={6}
                className="py-1.5 text-center text-blue-600 text-xs font-semibold border-r border-gray-200"
              >
                CALLS
              </th>
            )}
            <th className="px-3 py-1.5 text-center text-gray-500 text-xs font-semibold bg-gray-50">
              行權價格
            </th>
            {showPuts && (
              <th
                colSpan={6}
                className="py-1.5 text-center text-red-500 text-xs font-semibold border-l border-gray-200"
              >
                PUTS
              </th>
            )}
          </tr>
          <tr className="bg-white border-b border-gray-200">
            {showCalls && (
              <>
                <th className={thBase}>持倉量</th>
                <th className={thBase}>交易量</th>
                <th className={thBase}>IV</th>
                <th className={thBase}>要價</th>
                <th className={thBase}>出價</th>
                <th className={`${thBase} border-r border-gray-200`}>價格</th>
              </>
            )}
            <th className="px-3 py-1.5 text-center text-xs font-medium text-gray-500 bg-gray-50">
              {underlyingPrice > 0 && (
                <span className="inline-flex items-center gap-1 bg-amber-50 border border-amber-300 rounded px-2 py-0.5">
                  <span className="text-[10px] text-gray-400">現價</span>
                  <span className="text-xs font-mono font-bold text-amber-700">
                    ${underlyingPrice.toFixed(2)}
                  </span>
                </span>
              )}
            </th>
            {showPuts && (
              <>
                <th className={`${thBase} border-l border-gray-200 text-left`}>
                  價格
                </th>
                <th className={thBase}>出價</th>
                <th className={thBase}>要價</th>
                <th className={thBase}>IV</th>
                <th className={thBase}>交易量</th>
                <th className={thBase}>持倉量</th>
              </>
            )}
          </tr>
        </thead>
        <tbody>
          {(() => {
            const firstAboveIdx =
              underlyingPrice > 0
                ? rows.findIndex((r) => r.strike > underlyingPrice)
                : -1;
            return rows.map(({ strike, call, put }, idx) => {
              const callItm = call?.in_the_money ?? strike < underlyingPrice;
              const putItm = put?.in_the_money ?? strike > underlyingPrice;
              const isAtm =
                Math.abs(strike - underlyingPrice) <= underlyingPrice * 0.01;

              const callSelected = call?.contract_symbol === selectedContract;
              const putSelected = put?.contract_symbol === selectedContract;

              const rowBase =
                "border-b border-gray-100 hover:bg-blue-50 transition-colors";
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
              const strikeCallBg = callSelected
                ? "opt-call-selected"
                : "bg-gray-50";
              const strikePutBg = putSelected
                ? "opt-put-selected"
                : "bg-gray-50";

              const isLastBelow =
                firstAboveIdx > 0 && idx === firstAboveIdx - 1;

              return (
                <tr
                  key={strike}
                  className={`${rowBase} ${isAtm ? "ring-1 ring-inset ring-amber-400/60" : ""} ${isLastBelow ? "border-b-[3px] border-b-amber-400" : ""}`}
                >
                  {showCalls && (
                    <>
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
                    </>
                  )}

                  {/* Strike */}
                  <td className="py-1.5 text-sm bg-gray-50">
                    {filter === "both" ? (
                      <div className="flex items-center">
                        <div
                          className={`flex-1 py-1.5 text-right pr-1 font-mono font-semibold text-gray-700 tabular-nums select-none ${strikeCallBg}
                            ${call ? "cursor-pointer hover:text-blue-600 transition-colors" : "opacity-40"}`}
                          onClick={() => call && onSelect(call.contract_symbol)}
                        >
                          {strike.toFixed(2)}
                        </div>
                        <div className="w-px h-4 bg-gray-300 shrink-0" />
                        <div
                          className={`flex-1 py-1.5 text-left pl-1 font-mono font-semibold text-gray-700 tabular-nums select-none ${strikePutBg}
                            ${put ? "cursor-pointer hover:text-red-600 transition-colors" : "opacity-40"}`}
                          onClick={() => put && onSelect(put.contract_symbol)}
                        >
                          {strike.toFixed(2)}
                        </div>
                      </div>
                    ) : (
                      <div
                        className={`px-3 text-center font-mono font-semibold text-gray-700 tabular-nums select-none
                          ${showCalls && call ? "cursor-pointer hover:text-blue-600" : ""}
                          ${showPuts && put ? "cursor-pointer hover:text-red-600" : ""}`}
                        onClick={() => {
                          if (showCalls && call) onSelect(call.contract_symbol);
                          else if (showPuts && put) onSelect(put.contract_symbol);
                        }}
                      >
                        {strike.toFixed(2)}
                      </div>
                    )}
                  </td>

                  {showPuts && (
                    <>
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
                    </>
                  )}
                </tr>
              );
            });
          })()}
        </tbody>
      </table>
    </div>
  );
}
