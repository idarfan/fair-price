import Tippy from "@tippyjs/react";
import "tippy.js/dist/tippy.css";
import katex from "katex";
import "katex/dist/katex.min.css";
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

// ── KaTeX renderer ────────────────────────────────────────────────────────────

function KaTeXSpan({ formula }: { formula: string }) {
  const html = katex.renderToString(formula, { throwOnError: false, output: "html" });
  return <span dangerouslySetInnerHTML={{ __html: html }} />;
}

// ── Rich tooltip content ──────────────────────────────────────────────────────

interface TipDef {
  title: string;
  formula?: string;
  desc: string;
  example?: string;
}

function TipContent({ title, formula, desc, example }: TipDef) {
  return (
    <div style={{ minWidth: 210, maxWidth: 290, padding: "10px 12px", fontSize: 12, lineHeight: 1.55, background: "#fff", color: "#111827" }}>
      <div style={{ fontWeight: 700, fontSize: 13, paddingBottom: 5, marginBottom: 5, borderBottom: "1px solid #e5e7eb" }}>
        {title}
      </div>
      {formula && (
        <div style={{ background: "#f9fafb", border: "1px solid #e5e7eb", borderRadius: 4, padding: "6px 8px", marginBottom: 6, textAlign: "center", overflowX: "auto" }}>
          <KaTeXSpan formula={formula} />
        </div>
      )}
      <div style={{ color: "#374151", fontSize: 11, lineHeight: 1.65 }}>{desc}</div>
      {example && (
        <div style={{ color: "#92400e", fontSize: 11, marginTop: 5, background: "#fef3c7", padding: "3px 6px", borderRadius: 3 }}>
          <span style={{ fontWeight: 600 }}>範例：</span>{example}
        </div>
      )}
    </div>
  );
}

// ── Tooltip header cell ───────────────────────────────────────────────────────

function ColTh({ label, tip, className = "" }: { label: string; tip: TipDef; className?: string }) {
  return (
    <th className={`px-1.5 py-1 text-[10px] font-medium text-gray-500 uppercase tracking-wide text-right whitespace-nowrap ${className}`}>
      <Tippy
        content={<TipContent {...tip} />}
        placement="bottom"
        arrow={true}
        interactive={false}
        maxWidth={310}
        delay={[150, 0]}
      >
        <span className="cursor-help inline-flex items-center gap-0.5">
          {label}
          <span className="text-gray-300 text-[8px] leading-none">ⓘ</span>
        </span>
      </Tippy>
    </th>
  );
}

// ── Formatters ────────────────────────────────────────────────────────────────

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

const RISK_FREE_RATE = 0.043;

function blackScholes(S: number, K: number, T: number, sigma: number, type: "call" | "put"): number | null {
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

// ── Derived metrics ───────────────────────────────────────────────────────────

interface DerivedMetrics {
  spread: number | null;
  theor: number | null;
  bidPct: number | null;
  askPct: number | null;
  annBid: number | null;
}

function calcDerived(
  snap: OptionSnapshotRow | null,
  type: "call" | "put",
  underlyingPrice: number,
  strike: number,
  T: number,
  dte: number,
): DerivedMetrics {
  if (!snap) return { spread: null, theor: null, bidPct: null, askPct: null, annBid: null };
  const bid = snap.bid ?? 0;
  const ask = snap.ask ?? 0;
  const sIv = snap.implied_volatility ?? 0;
  const spread = bid > 0 ? (ask - bid) / bid * 100 : null;
  const theor = sIv > 0 && T > 0 && underlyingPrice > 0
    ? blackScholes(underlyingPrice, strike, T, sIv, type)
    : null;
  const bidPct = underlyingPrice > 0 ? bid / underlyingPrice * 100 : null;
  const askPct = underlyingPrice > 0 ? ask / underlyingPrice * 100 : null;
  const annBid = bidPct != null && dte > 0 ? bidPct * 365 / dte : null;
  return { spread, theor, bidPct, askPct, annBid };
}

// ── Tooltip definitions ───────────────────────────────────────────────────────

const rStr = (RISK_FREE_RATE * 100).toFixed(1);

const TIPS: Record<string, TipDef> = {
  distance: {
    title: "距離 (Distance)",
    formula: "K - S",
    desc: "行權價 K 與現價 S 的差額（帶符號）。正值為 OTM（虛值），負值為 ITM（實值）。",
    example: "Strike $60, 現價 $56.30 → +3.70",
  },
  relDist: {
    title: "相對距離 (Rel dist)",
    formula: "\\dfrac{K - S}{S} \\times 100\\%",
    desc: "行權價偏離現價的百分比，反映期權的虛值程度。越接近 0% 代表越接近平值 ATM。",
    example: "+3.70 ÷ 56.30 × 100% ≈ +6.57%",
  },
  iv: {
    title: "隱含波動率 (IV)",
    formula: "\\sigma_{\\text{impl}} = \\mathrm{BS}^{-1}(\\text{Market Price})",
    desc: "由期權市場價格反推的年化波動率。IV 越高期權越貴，代表市場預期未來波動越大。",
  },
  theor: {
    title: "Black-Scholes 理論價值 (Theor)",
    formula: "C = S \\cdot N(d_1) - K e^{-rT} N(d_2)",
    desc: `無風險利率 r = ${rStr}%，T = DTE ÷ 365。d₁ = [ln(S/K) + (r + σ²/2)T] / (σ√T)，d₂ = d₁ − σ√T。不含股息調整。`,
  },
  bid: {
    title: "出價 (Bid)",
    desc: "市場上買方最高願意支付的價格。Sell to Open（賣出開倉）時，所收權利金以此為基準。",
  },
  ask: {
    title: "要價 (Ask)",
    desc: "市場上賣方最低願意接受的價格。Buy to Open（買入開倉）時，所付權利金以此為基準。",
  },
  spread: {
    title: "買賣價差% (Spread%)",
    formula: "\\dfrac{\\text{Ask} - \\text{Bid}}{\\text{Bid}} \\times 100\\%",
    desc: "Spread% 越低流動性越好，進出成本越低。通常低於 5% 表示流動性尚可。",
    example: "Bid $1.00, Ask $1.05 → 5%",
  },
  bidPct: {
    title: "Bid 佔現價比 (Bid%)",
    formula: "\\dfrac{\\text{Bid}}{S} \\times 100\\%",
    desc: "賣出 Covered Call 或 Cash-Secured Put 的單期收益率，反映期權權利金相對標的現價的比例。",
    example: "Bid $1.40, 現價 $56.30 → 2.49%",
  },
  askPct: {
    title: "Ask 佔現價比 (Ask%)",
    formula: "\\dfrac{\\text{Ask}}{S} \\times 100\\%",
    desc: "買入期權時的成本佔標的現價比例，用於比較不同行權價的相對成本高低。",
  },
  annBid: {
    title: "年化 Bid% (Ann bid%)",
    formula: "\\text{Bid\\%} \\times \\dfrac{365}{\\text{DTE}}",
    desc: "將 Bid% 換算為年化收益率。Covered Call / Wheel 策略中最常用的效率指標，反映每年潛在收益率。",
    example: "Bid% 2.49%, DTE 26 → 年化 ≈ 34.9%",
  },
  ltp: {
    title: "最近成交價 (LTP)",
    desc: "Last Traded Price。可能與 Bid/Ask 有落差，因最近成交不代表當前最佳報價。",
  },
  volume: {
    title: "今日成交量 (交易量)",
    desc: "當日所有成交合約筆數的加總。成交量越高代表當日交易越活躍，但不反映持倉狀況。",
  },
  oi: {
    title: "未平倉量 (持倉量)",
    desc: "Open Interest：目前市場上尚未結算的合約總數。OI 越高代表市場參與度越高，與成交量結合可判斷市場動向。",
  },
};

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

  const strikeBadgeTh = (
    <th className="px-2 py-1.5 text-center text-xs font-medium text-gray-500 bg-gray-50">
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

  const expandedHeaders = (
    <>
      <ColTh label="距離"   tip={TIPS.distance} />
      <ColTh label="偏離%"  tip={TIPS.relDist} />
      <ColTh label="IV"     tip={TIPS.iv} />
      <ColTh label="理論值" tip={TIPS.theor} />
      <ColTh label="出價"   tip={TIPS.bid} />
      <ColTh label="要價"   tip={TIPS.ask} />
      <ColTh label="差價%"  tip={TIPS.spread} />
      <ColTh label="Bid%"   tip={TIPS.bidPct} />
      <ColTh label="Ask%"   tip={TIPS.askPct} />
      <ColTh label="年化%"  tip={TIPS.annBid} />
      <ColTh label="LTP"    tip={TIPS.ltp} />
      <ColTh label="量"     tip={TIPS.volume} />
      <ColTh label="倉"     tip={TIPS.oi} />
    </>
  );

  return (
    <div className="w-full overflow-x-auto">
      <table
        className="w-full border-collapse text-xs"
        style={{ tableLayout: "fixed", minWidth: single ? 640 : 560 }}
      >
        <colgroup>
          {single ? (
            <>
              <col style={{ width: "9%" }} />
              <col style={{ width: "7.5%" }} />
              <col style={{ width: "7.5%" }} />
              <col style={{ width: "7%" }} />
              <col style={{ width: "7.5%" }} />
              <col style={{ width: "7%" }} />
              <col style={{ width: "7%" }} />
              <col style={{ width: "7.5%" }} />
              <col style={{ width: "6.5%" }} />
              <col style={{ width: "6.5%" }} />
              <col style={{ width: "8%" }} />
              <col style={{ width: "7%" }} />
              <col style={{ width: "7.5%" }} />
              <col style={{ width: "7.5%" }} />
            </>
          ) : (
            <>
              {showCalls && (
                <>
                  <col style={{ width: "8%" }} />
                  <col style={{ width: "7%" }} />
                  <col style={{ width: "8%" }} />
                  <col style={{ width: "8%" }} />
                  <col style={{ width: "8%" }} />
                  <col style={{ width: "8%" }} />
                </>
              )}
              <col style={{ width: "12%" }} />
              {showPuts && (
                <>
                  <col style={{ width: "8%" }} />
                  <col style={{ width: "8%" }} />
                  <col style={{ width: "8%" }} />
                  <col style={{ width: "8%" }} />
                  <col style={{ width: "7%" }} />
                  <col style={{ width: "8%" }} />
                </>
              )}
            </>
          )}
        </colgroup>

        {/* ── THEAD ── */}
        <thead>
          {/* Row 1: section labels */}
          <tr className="bg-gray-50 border-b border-gray-200">
            {single && (
              <th className="px-2 py-1.5 text-center text-gray-500 text-xs font-semibold bg-gray-50">
                行權價格
              </th>
            )}
            {showCalls && (
              <th
                colSpan={single ? 13 : 6}
                className={`py-1.5 text-center text-blue-600 text-xs font-semibold ${!single ? "border-r border-gray-200" : ""}`}
              >
                CALLS
              </th>
            )}
            {!single && (
              <th className="px-2 py-1.5 text-center text-gray-500 text-xs font-semibold bg-gray-50">
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
            {single && strikeBadgeTh}
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
            {showCalls && single && expandedHeaders}
            {!single && strikeBadgeTh}
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
            {showPuts && single && expandedHeaders}
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
              const snap = call ?? put;
              const dte  = snap?.expiration ? calcDte(snap.expiration) : 0;
              const T    = dte / 365;

              const callItm = call?.in_the_money ?? strike < underlyingPrice;
              const putItm  = put?.in_the_money  ?? strike > underlyingPrice;
              const isAtm   = Math.abs(strike - underlyingPrice) <= underlyingPrice * 0.01;
              const callSel = call?.contract_symbol === selectedContract;
              const putSel  = put?.contract_symbol  === selectedContract;
              const isLB    = firstAboveIdx > 0 && idx === firstAboveIdx - 1;

              const callBg = callSel ? "opt-call-selected" : callItm ? "opt-call-itm" : "bg-white";
              const putBg  = putSel  ? "opt-put-selected"  : putItm  ? "opt-put-itm"  : "bg-white";
              const strikeCallBg = callSel ? "opt-call-selected" : "bg-gray-50";
              const strikePutBg  = putSel  ? "opt-put-selected"  : "bg-gray-50";

              const rowCls = [
                "border-b border-gray-100 hover:bg-blue-50 transition-colors",
                isAtm ? "ring-1 ring-inset ring-amber-400/60" : "",
                isLB  ? "border-b-[3px] border-b-amber-400"  : "",
              ].filter(Boolean).join(" ");

              const dist    = underlyingPrice > 0 ? strike - underlyingPrice : null;
              const relDist = dist != null && underlyingPrice > 0 ? dist / underlyingPrice * 100 : null;

              const cd = calcDerived(call, "call", underlyingPrice, strike, T, dte);
              const pd = calcDerived(put,  "put",  underlyingPrice, strike, T, dte);

              const strikeTd = (
                <td key="strike" className="py-1.5 bg-gray-50">
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
                      className={`px-2 text-center font-mono font-semibold text-gray-700 tabular-nums select-none ${showCalls && call ? "cursor-pointer hover:text-blue-600" : ""} ${showPuts && put ? "cursor-pointer hover:text-red-600" : ""}`}
                      onClick={() => {
                        if (showCalls && call) onSelect(call.contract_symbol);
                        else if (showPuts && put) onSelect(put.contract_symbol);
                      }}
                    >{strike.toFixed(2)}</div>
                  )}
                </td>
              );

              function expandedCells(
                s: OptionSnapshotRow | null,
                d: DerivedMetrics,
                bg: string,
                onClick: () => void,
              ) {
                const c = `px-1.5 py-1 text-right tabular-nums truncate ${bg} cursor-pointer`;
                return (
                  <>
                    <td className={c} onClick={onClick}>{fmtDollar(dist, true)}</td>
                    <td className={c} onClick={onClick}>{fmtPct(relDist)}</td>
                    <td className={c} onClick={onClick}>{fmtIv(s?.implied_volatility ?? null)}</td>
                    <td className={`${c} text-violet-600`} onClick={onClick}>{fmtPrice(d.theor)}</td>
                    <td className={c} onClick={onClick}>{fmtPrice(s?.bid ?? null)}</td>
                    <td className={c} onClick={onClick}>{fmtPrice(s?.ask ?? null)}</td>
                    <td className={c} onClick={onClick}>{fmtPct(d.spread)}</td>
                    <td className={c} onClick={onClick}>{fmtPct(d.bidPct)}</td>
                    <td className={c} onClick={onClick}>{fmtPct(d.askPct)}</td>
                    <td className={`${c} font-semibold text-amber-700`} onClick={onClick}>{fmtPct(d.annBid)}</td>
                    <td className={c} onClick={onClick}>{fmtPrice(s?.last_price ?? null)}</td>
                    <td className={c} onClick={onClick}>{fmtInt(s?.volume ?? null)}</td>
                    <td className={c} onClick={onClick}>{fmtInt(s?.open_interest ?? null)}</td>
                  </>
                );
              }

              return (
                <tr key={strike} className={rowCls}>
                  {single && strikeTd}

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

                  {!single && strikeTd}

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
