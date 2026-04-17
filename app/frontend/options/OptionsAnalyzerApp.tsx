import React, { useState, useEffect, useCallback } from "react";
import {
  Group,
  Panel,
  Separator,
  useDefaultLayout,
  useGroupRef,
  type GroupImperativeHandle,
} from "react-resizable-panels";
import type {
  MarketOutlook,
  SentimentData,
  IvRankData,
  PayoffLeg,
} from "./types";
import { getStrategies, buildLegsForPrice } from "./strategies";
import { buildChartData, calcSummary } from "./payoff";
import OutlookSelector from "./components/OutlookSelector";
import StrategyRecommendList from "./components/StrategyRecommendList";
import StrategyDetailPanel from "./components/StrategyDetailPanel";
import PayoffChart from "./components/PayoffChart";
import SentimentPanel from "./components/SentimentPanel";
import { OcrResult } from "./components/ImageUploadZone";
import StockLogo from "../components/StockLogo";

// ─── Panel IDs & defaults ─────────────────────────────────────────────────────

const PANEL_IDS = {
  lrSidebar: "lr-sidebar",
  lrMain: "lr-main",
  tbChart: "tb-chart",
  tbBottom: "tb-bottom",
  ssLeft: "ss-left",
  ssRight: "ss-right",
} as const;

const STORAGE_IDS = {
  leftRight: "options-left-right",
  topBottom: "options-top-bottom",
  stratSplit: "options-strat-split",
} as const;

const DEFAULTS = {
  leftRight: { [PANEL_IDS.lrSidebar]: 13, [PANEL_IDS.lrMain]: 87 },
  topBottom: { [PANEL_IDS.tbChart]: 34, [PANEL_IDS.tbBottom]: 66 },
  stratSplit: { [PANEL_IDS.ssLeft]: 22, [PANEL_IDS.ssRight]: 78 },
} as const;

// ─── Panel Reset Button ───────────────────────────────────────────────────────

function PanelResetButton({
  leftRightRef,
  topBottomRef,
  stratSplitRef,
}: {
  leftRightRef: React.RefObject<GroupImperativeHandle | null>;
  topBottomRef: React.RefObject<GroupImperativeHandle | null>;
  stratSplitRef: React.RefObject<GroupImperativeHandle | null>;
}): React.ReactElement {
  const handleReset = () => {
    // 清除 localStorage — 下次頁面載入時使用預設值
    Object.values(STORAGE_IDS).forEach((id) => {
      localStorage.removeItem(`react-resizable-panels:${id}`);
    });
    // 立即更新目前面板
    leftRightRef.current?.setLayout(DEFAULTS.leftRight);
    topBottomRef.current?.setLayout(DEFAULTS.topBottom);
    stratSplitRef.current?.setLayout(DEFAULTS.stratSplit);
  };
  return (
    <button
      onClick={handleReset}
      title="還原面板預設大小"
      className="flex-shrink-0 text-xs text-gray-400 hover:text-gray-600 px-2 py-1 rounded hover:bg-gray-100 transition-colors"
    >
      ↺ 還原版面
    </button>
  );
}

// ─── AI 建議分段排版 ─────────────────────────────────────────────────────────

function RecommendationText({ text }: { text: string }) {
  const paragraphs = text
    .split(/\n+/)
    .flatMap((line) => line.split(/(?=\d+\.\s)/))
    .filter((s) => s.trim());

  return (
    <div className="flex flex-col gap-3">
      {paragraphs.map((para, i) => {
        const trimmed = para.trim();
        const isHeading = /^\d+\.\s/.test(trimmed) && trimmed.length < 60;
        if (isHeading) {
          return (
            <h4 key={i} className="text-sm font-bold text-gray-900 mt-1">
              {trimmed}
            </h4>
          );
        }
        const hasNumber = /^\d+\.\s/.test(trimmed);
        return (
          <p
            key={i}
            className={`text-sm text-gray-800 leading-relaxed break-words ${hasNumber ? "pl-4 border-l-2 border-blue-200" : ""}`}
          >
            {trimmed}
          </p>
        );
      })}
    </div>
  );
}

// ─── Types ────────────────────────────────────────────────────────────────────

interface LegRow extends PayoffLeg {
  id: number;
}

// ─── Custom Leg Editor ────────────────────────────────────────────────────────

const LEG_TYPES: PayoffLeg["type"][] = [
  "long_call",
  "short_call",
  "long_put",
  "short_put",
];
const LEG_LABELS: Record<PayoffLeg["type"], string> = {
  long_call: "Long Call",
  short_call: "Short Call",
  long_put: "Long Put",
  short_put: "Short Put",
  long_stock: "Long Stock",
  short_stock: "Short Stock",
};

function LegEditor({
  legs,
  onAdd,
  onRemove,
  onChange,
}: {
  legs: LegRow[];
  onAdd: () => void;
  onRemove: (id: number) => void;
  onChange: (
    id: number,
    field: keyof PayoffLeg,
    value: number | string,
  ) => void;
}) {
  return (
    <div className="flex flex-col gap-2">
      {legs.map((leg) => (
        <div key={leg.id} className="flex gap-1 items-center flex-wrap">
          <select
            value={leg.type}
            onChange={(e) => onChange(leg.id, "type", e.target.value)}
            className="text-xs border border-gray-200 rounded px-1 py-0.5 bg-white"
          >
            {LEG_TYPES.map((t) => (
              <option key={t} value={t}>
                {LEG_LABELS[t]}
              </option>
            ))}
          </select>
          <input
            type="number"
            placeholder="Strike"
            value={leg.strike || ""}
            onChange={(e) =>
              onChange(leg.id, "strike", parseFloat(e.target.value) || 0)
            }
            className="w-20 text-xs border border-gray-200 rounded px-1 py-0.5"
          />
          <input
            type="number"
            placeholder="Premium"
            step="0.01"
            value={leg.premium || ""}
            onChange={(e) =>
              onChange(leg.id, "premium", parseFloat(e.target.value) || 0)
            }
            className="w-20 text-xs border border-gray-200 rounded px-1 py-0.5"
          />
          <input
            type="number"
            placeholder="Qty"
            value={leg.quantity}
            onChange={(e) =>
              onChange(leg.id, "quantity", parseInt(e.target.value) || 1)
            }
            className="w-12 text-xs border border-gray-200 rounded px-1 py-0.5"
          />
          <button
            onClick={() => onRemove(leg.id)}
            className="text-red-400 hover:text-red-600 text-xs px-1"
          >
            ✕
          </button>
        </div>
      ))}
      <button
        onClick={onAdd}
        className="text-xs text-blue-500 hover:text-blue-700 text-left"
      >
        + 新增腳
      </button>
    </div>
  );
}

// ─── Symbol Search Bar ────────────────────────────────────────────────────────

function SymbolBar({
  symbol,
  price,
  loading,
  onSearch,
}: {
  symbol: string;
  price: number;
  loading: boolean;
  onSearch: (sym: string) => void;
}) {
  const [input, setInput] = useState("");

  const handleSubmit = (e: React.FormEvent<HTMLFormElement>) => {
    e.preventDefault();
    const sym = input.trim().toUpperCase();
    if (sym) onSearch(sym);
  };

  return (
    <form onSubmit={handleSubmit} className="flex items-center gap-2">
      <input
        value={input}
        onChange={(e) => setInput(e.target.value.toUpperCase())}
        placeholder="輸入美股代號"
        className="w-36 border border-gray-200 rounded-lg px-3 py-1.5 text-sm focus:outline-none focus:ring-2 focus:ring-blue-300"
      />
      <button
        type="submit"
        disabled={loading || !input.trim()}
        className="bg-blue-600 text-white text-sm px-4 py-1.5 rounded-lg hover:bg-blue-700 disabled:opacity-50 transition-colors flex-shrink-0"
      >
        {loading ? "載入…" : "分析"}
      </button>
      {symbol && price > 0 && (
        <>
          <StockLogo symbol={symbol} size="md" />
          <span className="text-sm text-gray-500 font-medium flex-shrink-0">
            {symbol} ${price.toFixed(2)}
          </span>
        </>
      )}
    </form>
  );
}

// ─── Header Upload Zone ───────────────────────────────────────────────────────

interface UploadContext {
  symbol: string;
  price: number;
  ivRank: IvRankData | null;
}

function HeaderUploadZone({
  onResult,
  context,
}: {
  onResult: (r: OcrResult) => void;
  context: UploadContext;
}) {
  const [dragging, setDragging] = useState(false);
  const [loading, setLoading] = useState(false);
  const [status, setStatus] = useState("");
  const inputRef = React.useRef<HTMLInputElement>(null);

  const processFile = async (file: File) => {
    if (!file.type.startsWith("image/")) {
      setStatus("請上傳圖片檔案");
      return;
    }
    setLoading(true);
    setStatus("分析中…");
    try {
      const fd = new FormData();
      fd.append("image", file);
      fd.append(
        "system_data",
        JSON.stringify({
          symbol: context.symbol,
          price: context.price,
          iv_rank: context.ivRank?.iv_rank ?? null,
          current_hv: context.ivRank?.current_hv ?? null,
          hv_high: context.ivRank?.hv_high ?? null,
          hv_low: context.ivRank?.hv_low ?? null,
          iv_comment: context.ivRank?.iv_comment ?? null,
          peers: context.ivRank?.peers ?? [],
        }),
      );
      const res = await fetch("/api/v1/options/analyze_image", {
        method: "POST",
        body: fd,
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data.error || "分析失敗");
      onResult(data as OcrResult);
      setStatus("✅ 分析完成");
      setTimeout(() => setStatus(""), 3000);
    } catch (e) {
      setStatus(e instanceof Error ? `❌ ${e.message}` : "❌ 錯誤");
    } finally {
      setLoading(false);
    }
  };

  const onDrop = (e: React.DragEvent) => {
    e.preventDefault();
    setDragging(false);
    const file = e.dataTransfer.files[0];
    if (file) processFile(file);
  };

  return (
    <div
      onClick={() => !loading && inputRef.current?.click()}
      onDragOver={(e) => {
        e.preventDefault();
        setDragging(true);
      }}
      onDragLeave={() => setDragging(false)}
      onDrop={onDrop}
      className={`flex-1 flex items-center justify-center gap-3 rounded-xl border-2 border-dashed cursor-pointer transition-colors select-none ${
        dragging
          ? "border-blue-400 bg-blue-50 text-blue-600"
          : loading
            ? "border-gray-200 bg-gray-50 text-gray-400 cursor-default"
            : "border-gray-300 bg-gray-50 hover:border-blue-400 hover:bg-blue-50 text-gray-500 hover:text-blue-600"
      }`}
    >
      <input
        ref={inputRef}
        type="file"
        accept="image/*"
        className="hidden"
        onChange={(e) => {
          const f = e.target.files?.[0];
          if (f) processFile(f);
        }}
      />
      {loading ? (
        <span className="text-sm">⏳ 分析中…</span>
      ) : status ? (
        <span className="text-sm font-medium">{status}</span>
      ) : (
        <>
          <span className="text-2xl">📸</span>
          <div className="text-sm">
            <div className="font-medium">拖放券商截圖至此</div>
            <div className="text-xs opacity-70">
              或點擊選取圖片，自動識別期權策略
            </div>
          </div>
        </>
      )}
    </div>
  );
}

// ─── Main App ─────────────────────────────────────────────────────────────────

let nextLegId = 1;

export default function OptionsAnalyzerApp({
  initialSymbol,
}: {
  initialSymbol: string;
}) {
  const [symbol, setSymbol] = useState(initialSymbol || "");
  const [price, setPrice] = useState(0);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");
  const [outlook, setOutlook] = useState<MarketOutlook>("bullish");
  const [ivRank, setIvRank] = useState<IvRankData | null>(null);
  const [sentiment, setSentiment] = useState<SentimentData | null>(null);
  const [selectedIdx, setSelectedIdx] = useState(0);
  const [legs, setLegs] = useState<LegRow[]>([]);
  const [activeTab, setActiveTab] = useState<"recommend" | "custom">(
    "recommend",
  );
  const [ocrResult, setOcrResult] = useState<OcrResult | null>(null);

  // Panel resize refs
  const leftRightRef = useGroupRef();
  const topBottomRef = useGroupRef();
  const stratSplitRef = useGroupRef();

  // Panel layout persistence
  const { defaultLayout: lrLayout, onLayoutChanged: lrOnChange } =
    useDefaultLayout({ id: STORAGE_IDS.leftRight });
  const { defaultLayout: tbLayout, onLayoutChanged: tbOnChange } =
    useDefaultLayout({ id: STORAGE_IDS.topBottom });
  const { defaultLayout: ssLayout, onLayoutChanged: ssOnChange } =
    useDefaultLayout({ id: STORAGE_IDS.stratSplit });

  const fetchData = useCallback(async (sym: string) => {
    setLoading(true);
    setError("");
    try {
      const [sentRes, ivRes] = await Promise.all([
        fetch(`/api/v1/options/${encodeURIComponent(sym)}/sentiment`),
        fetch(`/api/v1/options/${encodeURIComponent(sym)}/iv_rank`),
      ]);
      if (!sentRes.ok || !ivRes.ok) throw new Error("API 錯誤");
      const sentData: SentimentData = await sentRes.json();
      const ivData: IvRankData = await ivRes.json();
      setSentiment(sentData);
      setIvRank(ivData);
      setPrice(sentData.price);
    } catch (e) {
      setError(e instanceof Error ? e.message : "載入失敗");
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    if (symbol) fetchData(symbol);
  }, [symbol, fetchData]);

  const strategies = React.useMemo(
    () => getStrategies(outlook, ivRank?.iv_rank ?? 50),
    [outlook, ivRank],
  );

  useEffect(() => {
    setSelectedIdx(0);
    if (strategies.length > 0 && price > 0) {
      const builtLegs = buildLegsForPrice(strategies[0], price);
      setLegs(builtLegs.map((l) => ({ ...l, id: nextLegId++ })));
    }
  }, [strategies, price]);

  const handleSelectStrategy = (i: number) => {
    setSelectedIdx(i);
    const tpl = strategies[i];
    if (!tpl || price <= 0) return;
    const builtLegs = buildLegsForPrice(tpl, price);
    setLegs(builtLegs.map((l) => ({ ...l, id: nextLegId++ })));
  };

  const handleAddLeg = () => {
    setLegs((prev) => [
      ...prev,
      {
        id: nextLegId++,
        type: "long_call",
        strike: price > 0 ? Math.round(price / 5) * 5 : 100,
        premium: 1.0,
        quantity: 1,
      },
    ]);
    setActiveTab("custom");
  };

  const handleRemoveLeg = (id: number) =>
    setLegs((prev) => prev.filter((l) => l.id !== id));

  const handleChangeLeg = (
    id: number,
    field: keyof PayoffLeg,
    value: number | string,
  ) =>
    setLegs((prev) =>
      prev.map((l) => (l.id === id ? { ...l, [field]: value } : l)),
    );

  const chartData = React.useMemo(
    () =>
      legs.length > 0 && price > 0
        ? buildChartData(legs as PayoffLeg[], price)
        : [],
    [legs, price],
  );
  const summary = React.useMemo(
    () => (chartData.length > 0 ? calcSummary(chartData) : null),
    [chartData],
  );

  const handleSearch = async (sym: string) => {
    setSymbol(sym);
  };

  const handleOcrResult = useCallback((result: OcrResult) => {
    setOcrResult(result);
    if (result.symbol) setSymbol(result.symbol);
    if (result.outlook) setOutlook(result.outlook as MarketOutlook);
    if (result.legs.length > 0) {
      setLegs(
        result.legs.map(
          (l) =>
            ({
              ...l,
              id: nextLegId++,
              iv: l.iv ?? undefined,
              dte: l.dte ?? undefined,
              quantity: l.quantity,
            }) as LegRow,
        ),
      );
      setActiveTab("custom");
    }
  }, []);

  return (
    <div className="flex flex-col flex-1 min-h-0 w-full overflow-hidden bg-gray-50">
      {/* Header：左半輸入 + 右半上傳 + 還原版面按鈕 */}
      <div className="bg-white border-b border-gray-200 px-4 py-3 flex items-stretch gap-4 h-20">
        {/* 左半：標題 + 代號輸入 */}
        <div className="flex flex-col justify-center gap-1.5 flex-shrink-0">
          <h1 className="text-sm font-bold text-gray-800 leading-none">
            美股期權分析
          </h1>
          <SymbolBar
            symbol={symbol}
            price={price}
            loading={loading}
            onSearch={handleSearch}
          />
          {error && (
            <p className="text-xs text-red-500 leading-none">{error}</p>
          )}
        </div>

        {/* 分隔線 */}
        <div className="w-px bg-gray-200 flex-shrink-0" />

        {/* 右半：截圖上傳區 */}
        <HeaderUploadZone
          onResult={handleOcrResult}
          context={{ symbol, price, ivRank }}
        />

        {/* 分隔線 */}
        <div className="w-px bg-gray-200 flex-shrink-0" />

        {/* 還原版面按鈕 */}
        <div className="flex items-center flex-shrink-0">
          <PanelResetButton
            leftRightRef={leftRightRef}
            topBottomRef={topBottomRef}
            stratSplitRef={stratSplitRef}
          />
        </div>
      </div>

      {/* Body：三組可調整大小的 Panel */}

      {/* 外層水平分割：左側 sidebar ↔ 右側主區域 */}
      <Group
        orientation="horizontal"
        defaultLayout={lrLayout}
        onLayoutChanged={lrOnChange}
        groupRef={leftRightRef}
        className="flex-1 overflow-hidden min-h-0"
      >
        {/* 左側：Outlook + Sentiment */}
        <Panel
          id={PANEL_IDS.lrSidebar}
          defaultSize="13%"
          minSize="8%"
          maxSize="25%"
          className="overflow-y-auto overflow-x-hidden bg-white border-r border-gray-200"
        >
          <div className="p-2 flex flex-col gap-2 min-h-full">
            <OutlookSelector value={outlook} onChange={setOutlook} />
            <SentimentPanel sentiment={sentiment} ivRank={ivRank} />
          </div>
        </Panel>

        <Separator className="w-1.5 bg-gray-200 hover:bg-blue-400 cursor-col-resize transition-colors flex-shrink-0" />

        {/* 右側主區域 */}
        <Panel
          id={PANEL_IDS.lrMain}
          defaultSize="87%"
          className="flex flex-col overflow-hidden min-w-0"
        >
          {/* 垂直分割：損益圖 ↔ 策略區 */}
          <Group
            orientation="vertical"
            defaultLayout={tbLayout}
            onLayoutChanged={tbOnChange}
            groupRef={topBottomRef}
            className="flex-1 overflow-hidden"
          >
            {/* 上方：損益圖 */}
            <Panel
              id={PANEL_IDS.tbChart}
              defaultSize="34%"
              minSize="15%"
              maxSize="60%"
              className="flex flex-col bg-white border-b border-gray-200 overflow-hidden"
            >
              <div className="p-4 h-full flex flex-col">
                <div className="flex items-center gap-1.5 mb-2">
                  <span className="text-sm font-semibold text-gray-600">
                    📈 損益圖
                  </span>
                </div>
                <PayoffChart data={chartData} summary={summary} price={price} />
              </div>
            </Panel>

            <Separator className="h-1.5 bg-gray-200 hover:bg-blue-400 cursor-row-resize transition-colors flex-shrink-0" />

            {/* 下方：AI 分析（不參與 resize）+ 策略列表/解說 */}
            <Panel
              id={PANEL_IDS.tbBottom}
              defaultSize="66%"
              className="flex flex-col overflow-hidden min-h-0"
            >
              {/* AI 截圖分析（全寬，上傳後才顯示，不參與 resize） */}
              {ocrResult &&
                (ocrResult.recommendation || ocrResult.outlook_reason) && (
                  <div className="flex-shrink-0 border-b border-gray-200 bg-gradient-to-br from-blue-50 to-indigo-50 p-4 overflow-x-hidden">
                    <div className="flex-1 min-w-0 flex flex-col gap-2 overflow-hidden">
                      <div className="flex items-center justify-between gap-2">
                        <div className="flex items-center gap-2">
                          {ocrResult.symbol && (
                            <StockLogo symbol={ocrResult.symbol} size="md" />
                          )}
                          <p className="text-xs font-bold text-blue-700 uppercase tracking-wider">
                            AI 截圖分析
                            {ocrResult.symbol ? ` — ${ocrResult.symbol}` : ""}
                          </p>
                        </div>
                        <button
                          onClick={() => setOcrResult(null)}
                          className="text-blue-300 hover:text-blue-500 text-xs flex-shrink-0"
                        >
                          ✕ 關閉
                        </button>
                      </div>
                      {ocrResult.outlook_reason && (
                        <p className="text-sm text-blue-800 leading-relaxed break-words">
                          {ocrResult.outlook_reason}
                        </p>
                      )}
                      {ocrResult.recommendation && (
                        <div className="bg-white/70 rounded-xl p-4 max-h-96 overflow-y-auto">
                          <RecommendationText text={ocrResult.recommendation} />
                        </div>
                      )}
                    </div>
                  </div>
                )}

              {/* 水平分割：策略列表 ↔ 策略解說 */}
              <Group
                orientation="horizontal"
                defaultLayout={ssLayout}
                onLayoutChanged={ssOnChange}
                groupRef={stratSplitRef}
                className="flex-1 overflow-hidden min-h-0"
              >
                {/* 策略列表 */}
                <Panel
                  id={PANEL_IDS.ssLeft}
                  defaultSize="22%"
                  minSize="12%"
                  maxSize="40%"
                  className="flex flex-col bg-white border-r border-gray-100 overflow-hidden"
                >
                  <div className="flex border-b border-gray-100 flex-shrink-0">
                    <button
                      onClick={() => setActiveTab("recommend")}
                      className={`flex-1 py-2 text-xs font-medium transition-colors ${
                        activeTab === "recommend"
                          ? "bg-blue-50 text-blue-700 border-b-2 border-blue-600"
                          : "text-gray-500 hover:text-gray-700"
                      }`}
                    >
                      推薦策略
                    </button>
                    <button
                      onClick={() => setActiveTab("custom")}
                      className={`flex-1 py-2 text-xs font-medium transition-colors ${
                        activeTab === "custom"
                          ? "bg-blue-50 text-blue-700 border-b-2 border-blue-600"
                          : "text-gray-500 hover:text-gray-700"
                      }`}
                    >
                      自訂腳位
                    </button>
                  </div>
                  <div className="p-2 flex-1 overflow-y-auto">
                    {activeTab === "recommend" ? (
                      <StrategyRecommendList
                        strategies={strategies}
                        selectedIdx={selectedIdx}
                        onSelect={handleSelectStrategy}
                      />
                    ) : (
                      <LegEditor
                        legs={legs}
                        onAdd={handleAddLeg}
                        onRemove={handleRemoveLeg}
                        onChange={handleChangeLeg}
                      />
                    )}
                  </div>
                </Panel>

                <Separator className="w-1.5 bg-gray-100 hover:bg-blue-400 cursor-col-resize transition-colors flex-shrink-0" />

                {/* 策略解說 */}
                <Panel
                  id={PANEL_IDS.ssRight}
                  defaultSize="78%"
                  className="overflow-y-auto overflow-x-hidden bg-white"
                >
                  <div className="p-3">
                    <StrategyDetailPanel
                      template={strategies[selectedIdx] ?? null}
                      legs={legs as import("./types").PayoffLeg[]}
                      price={price}
                      summary={summary}
                    />
                  </div>
                </Panel>
              </Group>
            </Panel>
          </Group>
        </Panel>
      </Group>
    </div>
  );
}
