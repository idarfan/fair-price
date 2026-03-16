import { useState } from "react";

const WulfFairValue = () => {
  const [btcPrice, setBtcPrice] = useState(85000);
  const [discountRate, setDiscountRate] = useState(12);

  // ========== 基礎數據 ==========
  const currentPrice = 15.45;
  const sharesOutstanding = 420; // millions
  const marketCap = currentPrice * sharesOutstanding; // ~$6,489M
  const cash = 3300; // $3.3B in cash
  const debt = 3100; // $3.1B in debt
  const netDebt = debt - cash; // -$200M (net debt)
  const ev = marketCap + netDebt; // Enterprise Value

  // ========== 方法一：分析師共識目標價 ==========
  const analystTargets = [
    { source: "TipRanks (6位分析師)", target: 24.20, rating: "Strong Buy" },
    { source: "TickerNerd (17位分析師)", target: 23.00, rating: "Strong Buy" },
    { source: "Fintel (多位分析師)", target: 23.70, rating: "Buy" },
    { source: "MarketBeat", target: 20.69, rating: "Buy" },
    { source: "WallStreetZen (10位分析師)", target: 20.65, rating: "Buy" },
    { source: "Public.com (11位分析師)", target: 19.59, rating: "Buy" },
  ];
  const avgAnalystTarget = (analystTargets.reduce((s, a) => s + a.target, 0) / analystTargets.length).toFixed(2);

  // ========== 方法二：EV/Revenue 估值 ==========
  const rev2025 = 168.5; // $168.5M
  const rev2026E = 340; // ~$340M analyst consensus (143% growth)
  const rev2027E = 470; // ~$470M
  const rev2028E = 435; // ~$435M (stabilizing)

  const evRevMultiples = [
    { label: "保守 (10x)", multiple: 10 },
    { label: "基準 (15x)", multiple: 15 },
    { label: "樂觀 (20x)", multiple: 20 },
  ];

  const calcEVRevPrice = (rev, mult) => {
    const impliedEV = rev * mult;
    const impliedEquity = impliedEV - netDebt;
    return (impliedEquity / sharesOutstanding).toFixed(2);
  };

  // ========== 方法三：遠期 EPS 估值 ==========
  const epsEstimates = [
    { year: "2026E", eps: -0.32, peNA: true },
    { year: "2027E", eps: 0.24, pe: 60 },
    { year: "2028E", eps: 0.35, pe: 45 },
  ];

  const calcForwardPrice = (eps, pe) => (eps * pe).toFixed(2);
  const discountBack = (futurePrice, years) => (futurePrice / Math.pow(1 + discountRate / 100, years)).toFixed(2);

  // 2027 forward: EPS $0.24 × P/E 60 = $14.40, discounted 1yr
  const price2027Forward = 0.24 * 60;
  const price2027Discounted = (price2027Forward / (1 + discountRate / 100)).toFixed(2);

  // 2028 forward: EPS $0.35 × P/E 45 = $15.75, discounted 2yr
  const price2028Forward = 0.35 * 45;
  const price2028Discounted = (price2028Forward / Math.pow(1 + discountRate / 100, 2)).toFixed(2);

  // ========== 方法四：合約價值法 ==========
  const contractedRevenue = 12800; // $12.8B total contracted
  const contractYears = 15; // avg contract ~15 years
  const annualContractRev = (contractedRevenue / contractYears).toFixed(0); // ~$853M/yr
  const hpcMargin = 0.77; // 77% adjusted HPC margin
  const annualHPCProfit = (annualContractRev * hpcMargin).toFixed(0); // ~$657M
  const steadyStateEPS = (annualHPCProfit / sharesOutstanding).toFixed(2); // ~$1.56

  // At a 25x PE on steady-state
  const steadyStatePrice = (steadyStateEPS * 25).toFixed(2);
  const steadyStateDiscounted = (steadyStatePrice / Math.pow(1 + discountRate / 100, 3)).toFixed(2);

  // ========== 綜合估值 ==========
  const method1 = parseFloat(avgAnalystTarget);
  const method2 = parseFloat(calcEVRevPrice(rev2026E, 15));
  const method3 = (parseFloat(price2027Discounted) + parseFloat(price2028Discounted)) / 2;
  const method4 = parseFloat(steadyStateDiscounted);

  const fairValueAvg = ((method1 + method2 + method3 + method4) / 4).toFixed(2);
  const upside = (((fairValueAvg / currentPrice) - 1) * 100).toFixed(1);

  const getRatingColor = (val) => {
    if (val >= 30) return "#16a34a";
    if (val >= 10) return "#ca8a04";
    if (val >= 0) return "#d97706";
    return "#dc2626";
  };

  return (
    <div className="min-h-screen bg-gray-950 text-gray-100 p-4 md:p-8 max-w-5xl mx-auto">
      {/* Header */}
      <div className="mb-8">
        <div className="flex items-center gap-3 mb-2">
          <span className="text-3xl font-bold text-white">WULF</span>
          <span className="text-lg text-gray-400">TeraWulf Inc.</span>
        </div>
        <p className="text-sm text-gray-500">公允價值分析 — 2026年3月6日</p>
      </div>

      {/* Key Metrics Bar */}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-3 mb-8">
        {[
          { label: "目前股價", value: `$${currentPrice}`, sub: "2026/03/04" },
          { label: "市值", value: `$${(marketCap / 1000).toFixed(1)}B`, sub: `${sharesOutstanding}M 股` },
          { label: "企業價值", value: `$${(ev / 1000).toFixed(1)}B`, sub: `淨債務 $${(netDebt / 1000).toFixed(1)}B` },
          { label: "FY2025 營收", value: `$${rev2025}M`, sub: "YoY +20.3%" },
        ].map((m, i) => (
          <div key={i} className="bg-gray-900 rounded-lg p-4 border border-gray-800">
            <p className="text-xs text-gray-500 mb-1">{m.label}</p>
            <p className="text-xl font-bold text-white">{m.value}</p>
            <p className="text-xs text-gray-500">{m.sub}</p>
          </div>
        ))}
      </div>

      {/* Fair Value Summary */}
      <div className="bg-gradient-to-r from-blue-900/30 to-purple-900/30 border border-blue-800/50 rounded-xl p-6 mb-8">
        <div className="flex flex-col md:flex-row items-start md:items-center justify-between gap-4">
          <div>
            <p className="text-sm text-blue-300 mb-1">綜合公允價值估算</p>
            <p className="text-4xl font-bold text-white">${fairValueAvg}</p>
            <p className="text-sm mt-1" style={{ color: getRatingColor(parseFloat(upside)) }}>
              {upside > 0 ? "▲" : "▼"} {upside}% vs 目前價格
            </p>
          </div>
          <div className="grid grid-cols-2 gap-3 text-sm">
            <div className="bg-gray-900/50 rounded-lg p-3">
              <p className="text-gray-400 text-xs">分析師共識</p>
              <p className="text-white font-semibold">${avgAnalystTarget}</p>
            </div>
            <div className="bg-gray-900/50 rounded-lg p-3">
              <p className="text-gray-400 text-xs">EV/Revenue</p>
              <p className="text-white font-semibold">${method2.toFixed(2)}</p>
            </div>
            <div className="bg-gray-900/50 rounded-lg p-3">
              <p className="text-gray-400 text-xs">遠期 EPS</p>
              <p className="text-white font-semibold">${method3.toFixed(2)}</p>
            </div>
            <div className="bg-gray-900/50 rounded-lg p-3">
              <p className="text-gray-400 text-xs">合約價值法</p>
              <p className="text-white font-semibold">${method4}</p>
            </div>
          </div>
        </div>
      </div>

      {/* Method 1: Analyst Consensus */}
      <div className="bg-gray-900 border border-gray-800 rounded-xl p-6 mb-6">
        <h2 className="text-lg font-bold text-white mb-4">📊 方法一：分析師共識目標價</h2>
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead>
              <tr className="text-gray-400 border-b border-gray-800">
                <th className="text-left py-2">來源</th>
                <th className="text-right py-2">目標價</th>
                <th className="text-right py-2">評級</th>
                <th className="text-right py-2">隱含上漲空間</th>
              </tr>
            </thead>
            <tbody>
              {analystTargets.map((a, i) => (
                <tr key={i} className="border-b border-gray-800/50">
                  <td className="py-2 text-gray-300">{a.source}</td>
                  <td className="py-2 text-right text-white font-medium">${a.target.toFixed(2)}</td>
                  <td className="py-2 text-right">
                    <span className="bg-green-900/40 text-green-400 px-2 py-0.5 rounded text-xs">{a.rating}</span>
                  </td>
                  <td className="py-2 text-right text-green-400">
                    +{(((a.target / currentPrice) - 1) * 100).toFixed(1)}%
                  </td>
                </tr>
              ))}
            </tbody>
            <tfoot>
              <tr className="border-t border-gray-700">
                <td className="py-2 font-bold text-white">平均目標價</td>
                <td className="py-2 text-right font-bold text-yellow-400">${avgAnalystTarget}</td>
                <td></td>
                <td className="py-2 text-right font-bold text-green-400">
                  +{(((avgAnalystTarget / currentPrice) - 1) * 100).toFixed(1)}%
                </td>
              </tr>
            </tfoot>
          </table>
        </div>
        <p className="text-xs text-gray-500 mt-3">
          * 近期 Cantor Fitzgerald 上調目標至 $24、Morgan Stanley 給予 $37 最高目標價
        </p>
      </div>

      {/* Method 2: EV/Revenue */}
      <div className="bg-gray-900 border border-gray-800 rounded-xl p-6 mb-6">
        <h2 className="text-lg font-bold text-white mb-4">📈 方法二：EV/Revenue 估值法</h2>
        <p className="text-sm text-gray-400 mb-4">
          以 2026E 預估營收 ~$340M（YoY +102%）為基礎，搭配不同 EV/Rev 倍數
        </p>
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead>
              <tr className="text-gray-400 border-b border-gray-800">
                <th className="text-left py-2">情境</th>
                <th className="text-right py-2">EV/Rev 倍數</th>
                <th className="text-right py-2">隱含 EV</th>
                <th className="text-right py-2">隱含股價</th>
              </tr>
            </thead>
            <tbody>
              {evRevMultiples.map((m, i) => (
                <tr key={i} className="border-b border-gray-800/50">
                  <td className="py-2 text-gray-300">{m.label}</td>
                  <td className="py-2 text-right text-white">{m.multiple}x</td>
                  <td className="py-2 text-right text-white">${((rev2026E * m.multiple) / 1000).toFixed(1)}B</td>
                  <td className="py-2 text-right font-medium" style={{ color: parseFloat(calcEVRevPrice(rev2026E, m.multiple)) > currentPrice ? "#4ade80" : "#f87171" }}>
                    ${calcEVRevPrice(rev2026E, m.multiple)}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
        <div className="mt-4 grid grid-cols-3 gap-2 text-xs">
          <div className="bg-gray-800 rounded p-2 text-center">
            <p className="text-gray-500">2026E 營收</p>
            <p className="text-white font-medium">$340M</p>
          </div>
          <div className="bg-gray-800 rounded p-2 text-center">
            <p className="text-gray-500">2027E 營收</p>
            <p className="text-white font-medium">$470M</p>
          </div>
          <div className="bg-gray-800 rounded p-2 text-center">
            <p className="text-gray-500">2028E 營收</p>
            <p className="text-white font-medium">$435M</p>
          </div>
        </div>
      </div>

      {/* Method 3: Forward EPS */}
      <div className="bg-gray-900 border border-gray-800 rounded-xl p-6 mb-6">
        <h2 className="text-lg font-bold text-white mb-4">💰 方法三：遠期 EPS 估值法</h2>
        <div className="flex items-center gap-4 mb-4">
          <label className="text-sm text-gray-400">折現率：</label>
          <input
            type="range" min={8} max={18} value={discountRate}
            onChange={e => setDiscountRate(parseInt(e.target.value))}
            className="flex-1"
          />
          <span className="text-white font-medium w-12 text-right">{discountRate}%</span>
        </div>
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead>
              <tr className="text-gray-400 border-b border-gray-800">
                <th className="text-left py-2">年度</th>
                <th className="text-right py-2">預估 EPS</th>
                <th className="text-right py-2">假設 P/E</th>
                <th className="text-right py-2">遠期目標價</th>
                <th className="text-right py-2">折現至今日</th>
              </tr>
            </thead>
            <tbody>
              <tr className="border-b border-gray-800/50">
                <td className="py-2 text-gray-300">2026E</td>
                <td className="py-2 text-right text-red-400">-$0.32</td>
                <td className="py-2 text-right text-gray-500">N/A (虧損)</td>
                <td className="py-2 text-right text-gray-500">N/A</td>
                <td className="py-2 text-right text-gray-500">N/A</td>
              </tr>
              <tr className="border-b border-gray-800/50">
                <td className="py-2 text-gray-300">2027E</td>
                <td className="py-2 text-right text-green-400">$0.24</td>
                <td className="py-2 text-right text-white">60x</td>
                <td className="py-2 text-right text-white">${price2027Forward.toFixed(2)}</td>
                <td className="py-2 text-right text-yellow-400">
                  ${(price2027Forward / (1 + discountRate / 100)).toFixed(2)}
                </td>
              </tr>
              <tr className="border-b border-gray-800/50">
                <td className="py-2 text-gray-300">2028E</td>
                <td className="py-2 text-right text-green-400">$0.35</td>
                <td className="py-2 text-right text-white">45x</td>
                <td className="py-2 text-right text-white">${price2028Forward.toFixed(2)}</td>
                <td className="py-2 text-right text-yellow-400">
                  ${(price2028Forward / Math.pow(1 + discountRate / 100, 2)).toFixed(2)}
                </td>
              </tr>
            </tbody>
          </table>
        </div>
        <p className="text-xs text-gray-500 mt-3">
          * 高 P/E 反映高成長 AI/HPC 基礎設施公司的市場估值慣例
        </p>
      </div>

      {/* Method 4: Contract Value */}
      <div className="bg-gray-900 border border-gray-800 rounded-xl p-6 mb-6">
        <h2 className="text-lg font-bold text-white mb-4">📋 方法四：合約價值法（長期穩態）</h2>
        <p className="text-sm text-gray-400 mb-4">
          基於已簽約 $12.8B 長期合約、522 MW HPC 容量，推算穩態獲利能力
        </p>
        <div className="grid grid-cols-2 md:grid-cols-4 gap-3 mb-4">
          {[
            { label: "簽約總額", value: "$12.8B" },
            { label: "平均合約年限", value: "~15 年" },
            { label: "年化合約營收", value: `$${annualContractRev}M` },
            { label: "HPC 調整後毛利率", value: "77%" },
          ].map((m, i) => (
            <div key={i} className="bg-gray-800 rounded-lg p-3 text-center">
              <p className="text-xs text-gray-500">{m.label}</p>
              <p className="text-white font-semibold">{m.value}</p>
            </div>
          ))}
        </div>
        <div className="bg-gray-800/50 rounded-lg p-4">
          <div className="flex justify-between text-sm mb-2">
            <span className="text-gray-400">穩態年利潤</span>
            <span className="text-white">${annualHPCProfit}M</span>
          </div>
          <div className="flex justify-between text-sm mb-2">
            <span className="text-gray-400">穩態 EPS</span>
            <span className="text-white">${steadyStateEPS}</span>
          </div>
          <div className="flex justify-between text-sm mb-2">
            <span className="text-gray-400">穩態目標價 (25x P/E)</span>
            <span className="text-white">${steadyStatePrice}</span>
          </div>
          <div className="flex justify-between text-sm border-t border-gray-700 pt-2">
            <span className="text-gray-400">折現至今日 ({discountRate}%, 3年)</span>
            <span className="text-yellow-400 font-bold">
              ${(steadyStatePrice / Math.pow(1 + discountRate / 100, 3)).toFixed(2)}
            </span>
          </div>
        </div>
        <p className="text-xs text-gray-500 mt-3">
          * 假設全部合約順利交付、不考慮額外稀釋與BTC挖礦收入
        </p>
      </div>

      {/* Key Business Catalysts */}
      <div className="bg-gray-900 border border-gray-800 rounded-xl p-6 mb-6">
        <h2 className="text-lg font-bold text-white mb-4">🔑 關鍵業務催化劑與風險</h2>
        <div className="grid md:grid-cols-2 gap-4">
          <div>
            <h3 className="text-green-400 font-semibold mb-2 text-sm">利多因素</h3>
            <ul className="text-sm text-gray-300 space-y-2">
              <li className="flex gap-2"><span className="text-green-400">✓</span> 522 MW HPC 合約已簽定，$12.8B 長期營收能見度</li>
              <li className="flex gap-2"><span className="text-green-400">✓</span> Google 信用增強擔保（Fluidstack 合約）</li>
              <li className="flex gap-2"><span className="text-green-400">✓</span> $6.5B 長期融資已到位，資金充裕（現金 $3.3B）</li>
              <li className="flex gap-2"><span className="text-green-400">✓</span> 2026年預計完成多棟建築交付（CB2B~CB5）</li>
              <li className="flex gap-2"><span className="text-green-400">✓</span> 電力成本優勢（$0.047/kWh），使用零碳能源</li>
              <li className="flex gap-2"><span className="text-green-400">✓</span> 2.9 GW 多區域長期開發管線</li>
            </ul>
          </div>
          <div>
            <h3 className="text-red-400 font-semibold mb-2 text-sm">風險因素</h3>
            <ul className="text-sm text-gray-300 space-y-2">
              <li className="flex gap-2"><span className="text-red-400">✗</span> 2025年淨虧損 $661M（含衍生品公允價值波動 $430M）</li>
              <li className="flex gap-2"><span className="text-red-400">✗</span> 股份稀釋嚴重（YoY +24%）</li>
              <li className="flex gap-2"><span className="text-red-400">✗</span> 高負債比（D/E = 4.39x）</li>
              <li className="flex gap-2"><span className="text-red-400">✗</span> BTC 挖礦收入持續下降（Q4 $26.1M vs Q3 $43.4M）</li>
              <li className="flex gap-2"><span className="text-red-400">✗</span> HPC 建設執行風險（工期與成本控制）</li>
              <li className="flex gap-2"><span className="text-red-400">✗</span> Beta 值 4.31，股價波動極大</li>
            </ul>
          </div>
        </div>
      </div>

      {/* Disclaimer */}
      <div className="bg-gray-900/50 border border-gray-800 rounded-lg p-4 text-xs text-gray-500">
        <p className="font-semibold text-gray-400 mb-1">⚠️ 免責聲明</p>
        <p>
          本分析僅供參考，不構成投資建議。所有估值模型均基於假設，實際結果可能與預測大幅偏離。
          投資前請進行獨立研究並考慮個人風險承受能力。過去表現不代表未來結果。
        </p>
      </div>
    </div>
  );
};

export default WulfFairValue;
