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

// ── Formatters ───────────────────────────────────────────────────────────────

function fmtPrice(v: number | null) {
  if (v == null || v === 0) return <span className="text-gray-300">—</span>;
  return <span>{v.toFixed(2)}</span>;
}
function fmtIv(v: number | null) {
  if (v == null || v === 0) return <span className="text-gray-300">—</span>;
  return <span>{(v * 100).toFixed(1)}%</span>;
}
function fmtInt(v: number | null) {
  if (v == null || v === 0) return <span className="text-gray-300">0</span>;
  return <span>{v.toLocaleString()}</span>;
}
function fmtPct(v: number | null) {
  if (v == null || !isFinite(v)) return <span className="text-gray-300">—</span>;
  return <span>{v.toFixed(2)}%</span>;
}
function fmtDollar(v: number | null, signed = false) {
  if (v == null) return <span className="text-gray-300">—</span>;
  const s = v.toFixed(2);
  return <span>{signed && v > 0 ? `+${s}` : s}</span>;
}

// ── Black-Scholes ─────────────────────────────────────────────────────────────

function normCDF(x: number): number {
  const a1 = 0.254829592, a2 = -0.284496736, a3 = 1.421413741;
  const a4 = -1.453152027, a5 = 1.061405429, p = 0.3275911;
  const sign = x < 0 ? -1 : 1;
  const ax = Math.abs(x) / Math.sqrt(2);
  const t = 1 / (1 + p * ax);
  const y = 1 - ((((a5 * t + a4) * t + a3) * t + a2) * t + a1) * t * Math.exp(-ax * ax);
  return 0.5 * (1 + sign * y);
}

const RISK_FREE_RATE = 0.043; // ~10yr US Treasury

function blackScholes(
  S: number, K: number, T: number, sigma: number, type: "call" | "put"
): number | null {
  if (T <= 0 || sigma <= 0 || S <= 0 || K <= 0) return null;
  const r = RISK_FREE_RATE;
  const d1 = (Math.log(S / K) + (r + 0.5 * sigma * sigma) * T) / (sigma * Math.sqrt(T));
  const d2 = d1 - sigma * Math.sqrt(T);
  if (type === "call") return S * normCDF(d1) - K * Math.exp(-r * T) * normCDF(d2);
  return K * Math.exp(-r * T) * normCDF(-d2) - S * normCDF(-d1);
}

function calcDte(expiration: string): number {
  const today = new Date(); today.setHours(0, 0, 0, 0);
  return Math.max(0, Math.round((new Date(expiration).getTime() - today.getTime()) / 86_400_000));
}

// ── Tooltip header cell ───────────────────────────────────────────────────────

function ColTh({
  label, tip, className = "",
}: { label: string; tip: string; className?: string }) {
  return (
    <th className={`px-2 py-1.5 text-xs font-medium text-gray-500 uppercase tracking-wider text-right ${className}`}>
      <span className="relative group inline-flex items-center gap-0.5 cursor-help">
        {label}
        <span className="text-gray-300 text-[9px] leading-none">ⓘ</span>
        <span className="absolute bottom-full right-0 mb-1.5 w-52 px-2.5 py-1.5 text-[11px] leading-snug bg-gray-900 text-gray-100 rounded-md shadow-lg opacity-0 group-hover:opacity-100 pointer-events-none transition-opacity duration-150 z-50 whitespace-normal text-left font-normal normal-case tracking-normal">
          {tip}
        </span>
      </span>
    </th>
  );
}

// ── Main component ────────────────────────────────────────────────────────────

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
  const showPuts  = filter !== "call";
  const single    = filter !== "both";

  const thBase = "px-2 py-1.5 text-xs font-medium text-gray-500 uppercase tracking-wider text-right";
  const thL    = `${thBase} border-r border-gray-200`;
  const thR    = `${thBase} border-l border-gray-200 text-left`;

  // ── Strike badge th (reused in multiple positions) ─────────────────────────
  const strikeBadgeTh = (
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
  );

  return (
    <div className="overflow-x-auto">
      <table className="w-full border-collapse text-xs">
        {/* ── THEAD ── */}
        <thead>
          {/* Row 1: section labels */}
          <tr className="bg-gray-50 border-b border-gray-200">
            {single && (
              <th className="px-3 py-1.5 text-center text-gray-500 text-xs font-semibold bg-gray-50">
                行權價格
              </th>
            )}
            {showCalls && !single && (
              <th colSpan={6} className="py-1.5 text-center text-blue-600 text-xs font-semibold border-r border-gray-200">
                CALLS
              </th>
            )}
            {showCalls && single && (
              <th colSpan={13} className="py-1.5 text-center text-blue-600 text-xs font-semibold">
                CALLS
              </th>
            )}
            {!single && (
              <th className="px-3 py-1.5 text-center text-gray-500 text-xs font-semibold bg-gray-50">
                行權價格
              </th>
            )}
            {showPuts && !single && (
              <th colSpan={6} className="py-1.5 text-center text-rose-600 text-xs font-semibold border-l border-gray-200">
                PUTS
              </th>
            )}
            {showPuts && single && (
              <th colSpan={13} className="py-1.5 text-center text-rose-600 text-xs font-semibold">
                PUTS
              </th>
            )}
          </tr>

          {/* Row 2: column headers */}
          <tr className="bg-white border-b border-gray-200">
            {/* Strike badge — always left in single-mode */}
            {single && strikeBadgeTh}

            {/* Calls compact (both-mode) */}
            {showCalls && !single && (
              <>
                <th className={thBase}>持倉量</th>
                <th className={thBase}>交易量</th>
                <th className={thBase}>IV</th>
                <th className={thBase}>要價</th>
                <th className={thBase}>出價</th>
                <th className={thL}>價格</th>
              </>
            )}

            {/* Calls expanded (single-mode) */}
            {showCalls && single && (
              <>
                <ColTh label="Distance"  tip="行權價格與現價的絕對距離（美元）" />
                <ColTh label="Rel dist"  tip="行權價格與現價的相對距離，等於 Distance ÷ 現價 × 100%" />
                <ColTh label="IV"        tip="隱含波動率（Implied Volatility），由市場期權價格反推出的年化波動率預期" />
                <ColTh label="Theor"     tip={`Black-Scholes 理論公平價值（假設無風險利率 ${(RISK_FREE_RATE * 100).toFixed(1)}%，不含股息）`} />
                <ColTh label="Bid"       tip="市場最高買入報價" />
                <ColTh label="Ask"       tip="市場最低賣出報價" />
                <ColTh label="Spread%"   tip="買賣價差佔 Bid 的百分比，越低代表流動性越好" />
                <ColTh label="Bid%"      tip="Bid ÷ 現價 × 100%，代表期權權利金佔標的價格的比例" />
                <ColTh label="Ask%"      tip="Ask ÷ 現價 × 100%" />
                <ColTh label="Ann bid%"  tip="年化 Bid%，= Bid% × 365 ÷ DTE，代表若賣出此期權的年化收益率" />
                <ColTh label="LTP"       tip="最近成交價（Last Traded Price）" />
                <ColTh label="交易量"    tip="今日成交量" />
                <ColTh label="持倉量"    tip="未平倉合約數量（Open Interest）" />
              </>
            )}

            {/* Strike centre (both-mode) */}
            {!single && strikeBadgeTh}

            {/* Puts compact (both-mode) */}
            {showPuts && !single && (
              <>
                <th className={thR}>價格</th>
                <th className={thBase}>出價</th>
                <th className={thBase}>要價</th>
                <th className={thBase}>IV</th>
                <th className={thBase}>交易量</th>
                <th className={thBase}>持倉量</th>
              </>
            )}

            {/* Puts expanded (single-mode) */}
            {showPuts && single && (
              <>
                <ColTh label="Distance"  tip="行權價格與現價的絕對距離（美元）" />
                <ColTh label="Rel dist"  tip="行權價格與現價的相對距離，等於 Distance ÷ 現價 × 100%" />
                <ColTh label="IV"        tip="隱含波動率（Implied Volatility），由市場期權價格反推出的年化波動率預期" />
                <ColTh label="Theor"     tip={`Black-Scholes 理論公平價值（假設無風險利率 ${(RISK_FREE_RATE * 100).toFixed(1)}%，不含股息）`} />
                <ColTh label="Bid"       tip="市場最高買入報價" />
                <ColTh label="Ask"       tip="市場最低賣出報價" />
                <ColTh label="Spread%"   tip="買賣價差佔 Bid 的百分比，越低代表流動性越好" />
                <ColTh label="Bid%"      tip="Bid ÷ 現價 × 100%，代表期權權利金佔標的價格的比例" />
                <ColTh label="Ask%"      tip="Ask ÷ 現價 × 100%" />
                <ColTh label="Ann bid%"  tip="年化 Bid%，= Bid% × 365 ÷ DTE，代表若賣出此期權的年化收益率" />
                <ColTh label="LTP"       tip="最近成交價（Last Traded Price）" />
                <ColTh label="交易量"    tip="今日成交量" />
                <ColTh label="持倉量"    tip="未平倉合約數量（Open Interest）" />
              </>
            )}
          </tr>
        </thead>

        {/* ── TBODY ── */}
        <tbody>
          {(() => {
            const firstAboveIdx =
              underlyingPrice > 0
                ? rows.findIndex((r) => r.strike > underlyingPrice)
                : -1;

            return rows.map(({ strike, call, put }, idx) => {
              const snap     = call ?? put;
              const dte      = snap?.expiration ? calcDte(snap.expiration) : 0;
              const T        = dte / 365;
              const iv       = (call ?? put)?.implied_volatility ?? null;

              const callItm  = call?.in_the_money ?? strike < underlyingPrice;
              const putItm   = put?.in_the_money  ?? strike > underlyingPrice;
              const isAtm    = Math.abs(strike - underlyingPrice) <= underlyingPrice * 0.01;
              const callSel  = call?.contract_symbol === selectedContract;
              const putSel   = put?.contract_symbol  === selectedContract;
              const isLB     = firstAboveIdx > 0 && idx === firstAboveIdx - 1;

              const callBg    = callSel ? "opt-call-selected" : callItm ? "opt-call-itm" : "bg-white";
              const putBg     = putSel  ? "opt-put-selected"  : putItm  ? "opt-put-itm"  : "bg-white";
              const strikeCallBg = callSel ? "opt-call-selected" : "bg-gray-50";
              const strikePutBg  = putSel  ? "opt-put-selected"  : "bg-gray-50";

              const rowBase = "border-b border-gray-100 hover:bg-blue-50 transition-colors";
              const rowCls  = `${rowBase} ${isAtm ? "ring-1 ring-inset ring-amber-400/60" : ""} ${isLB ? "border-b-[3px] border-b-amber-400" : ""}`;

              // ── Derived metrics ─────────────────────────────────────────
              const dist     = underlyingPrice > 0 ? strike - underlyingPrice : null;
              const relDist  = dist != null && underlyingPrice > 0 ? dist / underlyingPrice * 100 : null;

              function derived(snap: OptionSnapshotRow | null, type: "call" | "put") {
                if (!snap) return null;
                const bid    = snap.bid ?? 0;
                const ask    = snap.ask ?? 0;
                const sIv    = snap.implied_volatility ?? 0;
                const spread = bid > 0 ? (ask - bid) / bid * 100 : null;
                const theor  = sIv > 0 && T > 0 && underlyingPrice > 0
                  ? blackScholes(underlyingPrice, strike, T, sIv, type)
                  : null;
                const bidPct  = underlyingPrice > 0 ? bid / underlyingPrice * 100 : null;
                const askPct  = underlyingPrice > 0 ? ask / underlyingPrice * 100 : null;
                const annBid  = bidPct != null && dte > 0 ? bidPct * 365 / dte : null;
                return { spread, theor, bidPct, askPct, annBid };
              }

              const cd = derived(call, "call");
              const pd = derived(put,  "put");

              // ── Strike td ───────────────────────────────────────────────
              const strikeTd = (
                <td key="strike" className="py-1.5 text-sm bg-gray-50">
                  {!single ? (
                    <div className="flex items-center">
                      <div
                        className={`flex-1 py-1.5 text-right pr-1 font-mono font-semibold text-gray-700 tabular-nums select-none ${strikeCallBg} ${call ? "cursor-pointer hover:text-blue-600 transition-colors" : "opacity-40"}`}
                        onClick={() => call && onSelect(call.contract_symbol)}
                      >{strike.toFixed(2)}</div>
                      <div className="w-px h-4 bg-gray-300 shrink-0" />
                      <div
                        className={`flex-1 py-1.5 text-left pl-1 font-mono font-semibold text-gray-700 tabular-nums select-none ${strikePutBg} ${put ? "cursor-pointer hover:text-red-600 transition-colors" : "opacity-40"}`}
                        onClick={() => put && onSelect(put.contract_symbol)}
                      >{strike.toFixed(2)}</div>
                    </div>
                  ) : (
                    <div
                      className={`px-3 text-center font-mono font-semibold text-gray-700 tabular-nums select-none ${showCalls && call ? "cursor-pointer hover:text-blue-600" : ""} ${showPuts && put ? "cursor-pointer hover:text-red-600" : ""}`}
                      onClick={() => {
                        if (showCalls && call) onSelect(call.contract_symbol);
                        else if (showPuts && put) onSelect(put.contract_symbol);
                      }}
                    >{strike.toFixed(2)}</div>
                  )}
                </td>
              );

              // ── Expanded cells for single-mode ──────────────────────────
              function expandedCells(snap: OptionSnapshotRow | null, d: ReturnType<typeof derived>, bg: string, onClick: () => void) {
                const cls = `px-2 py-1.5 text-right tabular-nums ${bg} cursor-pointer`;
                return (
                  <>
                    <td className={cls} onClick={onClick}>{fmtDollar(dist, true)}</td>
                    <td className={cls} onClick={onClick}>{fmtPct(relDist)}</td>
                    <td className={cls} onClick={onClick}>{fmtIv(snap?.implied_volatility ?? null)}</td>
                    <td className={`${cls} text-violet-600`} onClick={onClick}>{fmtPrice(d?.theor ?? null)}</td>
                    <td className={cls} onClick={onClick}>{fmtPrice(snap?.bid ?? null)}</td>
                    <td className={cls} onClick={onClick}>{fmtPrice(snap?.ask ?? null)}</td>
                    <td className={cls} onClick={onClick}>{fmtPct(d?.spread ?? null)}</td>
                    <td className={cls} onClick={onClick}>{fmtPct(d?.bidPct ?? null)}</td>
                    <td className={cls} onClick={onClick}>{fmtPct(d?.askPct ?? null)}</td>
                    <td className={`${cls} font-semibold text-amber-700`} onClick={onClick}>{fmtPct(d?.annBid ?? null)}</td>
                    <td className={cls} onClick={onClick}>{fmtPrice(snap?.last_price ?? null)}</td>
                    <td className={cls} onClick={onClick}>{fmtInt(snap?.volume ?? null)}</td>
                    <td className={cls} onClick={onClick}>{fmtInt(snap?.open_interest ?? null)}</td>
                  </>
                );
              }

              return (
                <tr key={strike} className={rowCls}>
                  {/* Strike left in single-mode */}
                  {single && strikeTd}

                  {/* Calls */}
                  {showCalls && !single && (
                    <>
                      <td className={`px-2 py-1.5 text-right tabular-nums text-blue-600 ${callBg} cursor-pointer`} onClick={() => call && onSelect(call.contract_symbol)}>{fmtInt(call?.open_interest ?? null)}</td>
                      <td className={`px-2 py-1.5 text-right tabular-nums text-blue-600 ${callBg} cursor-pointer`} onClick={() => call && onSelect(call.contract_symbol)}>{fmtInt(call?.volume ?? null)}</td>
                      <td className={`px-2 py-1.5 text-right tabular-nums text-indigo-600 ${callBg} cursor-pointer`} onClick={() => call && onSelect(call.contract_symbol)}>{fmtIv(call?.implied_volatility ?? null)}</td>
                      <td className={`px-2 py-1.5 text-right tabular-nums text-gray-600 ${callBg} cursor-pointer`} onClick={() => call && onSelect(call.contract_symbol)}>{fmtPrice(call?.ask ?? null)}</td>
                      <td className={`px-2 py-1.5 text-right tabular-nums text-blue-700 ${callBg} cursor-pointer`} onClick={() => call && onSelect(call.contract_symbol)}>{fmtPrice(call?.bid ?? null)}</td>
                      <td className={`px-2 py-1.5 text-right tabular-nums text-gray-800 font-medium border-r border-gray-200 ${callBg} cursor-pointer`} onClick={() => call && onSelect(call.contract_symbol)}>{fmtPrice(call?.last_price ?? null)}</td>
                    </>
                  )}
                  {showCalls && single && expandedCells(call, cd, callBg, () => call && onSelect(call.contract_symbol))}

                  {/* Strike centre in both-mode */}
                  {!single && strikeTd}

                  {/* Puts */}
                  {showPuts && !single && (
                    <>
                      <td className={`px-2 py-1.5 text-right tabular-nums text-gray-800 font-medium border-l border-gray-200 ${putBg} cursor-pointer`} onClick={() => put && onSelect(put.contract_symbol)}>{fmtPrice(put?.last_price ?? null)}</td>
                      <td className={`px-2 py-1.5 text-right tabular-nums text-blue-700 ${putBg} cursor-pointer`} onClick={() => put && onSelect(put.contract_symbol)}>{fmtPrice(put?.bid ?? null)}</td>
                      <td className={`px-2 py-1.5 text-right tabular-nums text-gray-600 ${putBg} cursor-pointer`} onClick={() => put && onSelect(put.contract_symbol)}>{fmtPrice(put?.ask ?? null)}</td>
                      <td className={`px-2 py-1.5 text-right tabular-nums text-indigo-600 ${putBg} cursor-pointer`} onClick={() => put && onSelect(put.contract_symbol)}>{fmtIv(put?.implied_volatility ?? null)}</td>
                      <td className={`px-2 py-1.5 text-right tabular-nums text-blue-600 ${putBg} cursor-pointer`} onClick={() => put && onSelect(put.contract_symbol)}>{fmtInt(put?.volume ?? null)}</td>
                      <td className={`px-2 py-1.5 text-right tabular-nums text-blue-600 ${putBg} cursor-pointer`} onClick={() => put && onSelect(put.contract_symbol)}>{fmtInt(put?.open_interest ?? null)}</td>
                    </>
                  )}
                  {showPuts && single && expandedCells(put, pd, putBg, () => put && onSelect(put.contract_symbol))}
                </tr>
              );
            });
          })()}
        </tbody>
      </table>
    </div>
  );
}
