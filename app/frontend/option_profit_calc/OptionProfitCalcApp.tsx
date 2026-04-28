import { useState, useEffect, useRef } from "react";

interface StockInfo {
  symbol: string;
  company_name: string;
  price: number;
}

interface CalcResult {
  sellPrice: number;
  totalCost: number;
  priceDiff: number;
  returnPct: number;
}

function calcSellPrice(
  purchasePrice: number,
  contracts: number,
  targetProfit: number,
): CalcResult {
  const shares = contracts * 100;
  const totalCost = purchasePrice * shares;
  const sellPrice = purchasePrice + targetProfit / shares;
  const priceDiff = sellPrice - purchasePrice;
  const returnPct = (targetProfit / totalCost) * 100;
  return { sellPrice, totalCost, priceDiff, returnPct };
}

function fmt(n: number, decimals = 2) {
  return n.toLocaleString("en-US", {
    minimumFractionDigits: decimals,
    maximumFractionDigits: decimals,
  });
}

export function OptionProfitCalcApp() {
  const [ticker, setTicker] = useState("");
  const [stockInfo, setStockInfo] = useState<StockInfo | null>(null);
  const [fetchError, setFetchError] = useState("");
  const [loading, setLoading] = useState(false);
  const abortRef = useRef<AbortController | null>(null);

  const [purchasePrice, setPurchasePrice] = useState("");
  const [contracts, setContracts] = useState("");
  const [targetProfit, setTargetProfit] = useState("");

  useEffect(() => {
    const sym = ticker.trim().toUpperCase();
    if (!sym) {
      setStockInfo(null);
      setFetchError("");
      return;
    }

    const timer = setTimeout(async () => {
      abortRef.current?.abort();
      const ctrl = new AbortController();
      abortRef.current = ctrl;

      setLoading(true);
      setFetchError("");
      setStockInfo(null);
      try {
        const res = await fetch(
          `/api/v1/margin_positions/price_lookup?symbol=${encodeURIComponent(sym)}`,
          { signal: ctrl.signal },
        );
        const data = await res.json();
        if (!res.ok) {
          setFetchError(data.error ?? "查詢失敗");
          return;
        }
        setStockInfo({
          symbol: data.symbol,
          company_name: data.company_name,
          price: data.price,
        });
      } catch (err) {
        if ((err as Error).name !== "AbortError")
          setFetchError("網路錯誤，請稍後再試");
      } finally {
        setLoading(false);
      }
    }, 600);

    return () => clearTimeout(timer);
  }, [ticker]);

  const purchase = parseFloat(purchasePrice);
  const ctrs = parseInt(contracts, 10);
  const profit = parseFloat(targetProfit);
  const canCalc = purchase > 0 && ctrs > 0 && profit > 0;
  const result = canCalc ? calcSellPrice(purchase, ctrs, profit) : null;

  const inputClass =
    "w-full bg-gray-800 border border-gray-600 rounded-lg px-3 py-2 text-white text-sm " +
    "placeholder-gray-500 focus:outline-none focus:border-blue-500 focus:ring-1 focus:ring-blue-500 transition-colors";
  const labelClass = "block text-xs font-medium text-gray-400 mb-1";

  return (
    <div className="flex flex-col h-full bg-gray-900 text-white">
      {/* Header */}
      <div className="flex items-center gap-2 px-4 py-3 border-b border-gray-700">
        <span className="text-lg">🎯</span>
        <span className="text-sm font-semibold text-gray-100">
          期權收益計算器
        </span>
      </div>

      <div className="flex-1 overflow-y-auto p-4 space-y-5">
        {/* Section 1: Stock lookup */}
        <div className="space-y-2">
          <p className={labelClass}>股票代號</p>
          <div className="relative">
            <input
              type="text"
              value={ticker}
              onChange={(e) => setTicker(e.target.value.toUpperCase())}
              placeholder="e.g. AAPL"
              maxLength={10}
              className={inputClass}
            />
            {loading && (
              <span className="absolute right-3 top-1/2 -translate-y-1/2 text-gray-400 text-xs animate-pulse">
                查詢中…
              </span>
            )}
          </div>

          {fetchError && <p className="text-xs text-red-400">{fetchError}</p>}
          {stockInfo && (
            <div className="flex items-center justify-between bg-gray-800 rounded-lg px-3 py-2">
              <div>
                <span className="text-xs text-gray-400">
                  {stockInfo.symbol}
                </span>
                <span className="text-xs text-gray-500 ml-1 truncate">
                  {stockInfo.company_name}
                </span>
              </div>
              <div className="text-right">
                <span className="text-sm font-semibold text-green-400">
                  ${fmt(stockInfo.price)}
                </span>
                <span className="text-xs text-gray-500 ml-1">現價</span>
              </div>
            </div>
          )}
        </div>

        {/* Divider */}
        <div className="border-t border-gray-700" />

        {/* Section 2: Option inputs */}
        <div className="space-y-4">
          <div>
            <label className={labelClass}>期權購入價格（每股，美元）</label>
            <div className="relative">
              <span className="absolute left-3 top-1/2 -translate-y-1/2 text-gray-500 text-sm">
                $
              </span>
              <input
                type="number"
                min="0.01"
                step="0.01"
                value={purchasePrice}
                onChange={(e) => setPurchasePrice(e.target.value)}
                placeholder="0.00"
                className={`${inputClass} pl-7`}
              />
            </div>
          </div>

          <div>
            <label className={labelClass}>契約數量（1 契約 = 100 股）</label>
            <input
              type="number"
              min="1"
              step="1"
              value={contracts}
              onChange={(e) => setContracts(e.target.value)}
              placeholder="1"
              className={inputClass}
            />
            {ctrs > 0 && purchase > 0 && (
              <p className="text-xs text-gray-500 mt-1">
                持倉成本：${fmt(purchase * ctrs * 100)}（{ctrs * 100} 股）
              </p>
            )}
          </div>

          <div>
            <label className={labelClass}>預期獲利金額（美元）</label>
            <div className="relative">
              <span className="absolute left-3 top-1/2 -translate-y-1/2 text-gray-500 text-sm">
                $
              </span>
              <input
                type="number"
                min="1"
                step="1"
                value={targetProfit}
                onChange={(e) => setTargetProfit(e.target.value)}
                placeholder="500"
                className={`${inputClass} pl-7`}
              />
            </div>
          </div>
        </div>

        {/* Section 3: Result */}
        {result && (
          <>
            <div className="border-t border-gray-700" />
            <div className="rounded-xl bg-gray-800 border border-gray-700 overflow-hidden">
              <div className="px-4 py-2 bg-gray-750 border-b border-gray-700">
                <p className="text-xs font-semibold text-gray-400 uppercase tracking-wider">
                  建議賣出價格
                </p>
              </div>
              <div className="px-4 py-4 text-center">
                <p className="text-4xl font-bold text-yellow-400">
                  ${fmt(result.sellPrice)}
                </p>
                <p className="text-sm text-gray-400 mt-1">
                  +${fmt(result.priceDiff)}
                  <span className="mx-1 text-gray-600">·</span>
                  <span className="text-green-400">
                    +{fmt(result.returnPct, 1)}%
                  </span>
                </p>
              </div>
              <div className="border-t border-gray-700 px-4 py-3 space-y-1">
                {[
                  ["持倉成本", `$${fmt(result.totalCost)}`],
                  ["預期獲利", `$${fmt(profit)}`],
                  [
                    "需漲幅度",
                    `${fmt(((result.sellPrice - purchase) / purchase) * 100, 1)}%`,
                  ],
                ].map(([k, v]) => (
                  <div key={k} className="flex justify-between text-xs">
                    <span className="text-gray-500">{k}</span>
                    <span className="text-gray-300 font-medium">{v}</span>
                  </div>
                ))}
              </div>
            </div>
          </>
        )}
      </div>
    </div>
  );
}
