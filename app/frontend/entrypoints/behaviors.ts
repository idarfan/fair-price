/**
 * 頁面行為的統一掛載點（稽核 H-3）。
 *
 * 過去每個 Phlex 元件都用 `script { raw <<~JS.html_safe }` 把 JavaScript 內嵌在
 * Ruby heredoc 裡——不經 ESLint、不經 TypeScript、無法測試、無 source map，
 * 而且強迫 CSP 開 `script_src :unsafe_inline`。
 *
 * 現在元件只輸出一個標記：
 *
 *     div(data: { behavior: "iv-analysis" })
 *
 * 這支 entrypoint 掃描 `[data-behavior]`，用動態 import 只載入該頁真正需要的模組。
 * Vite 會把每個 behavior 切成獨立 chunk，沒出現在頁面上的就完全不會下載。
 *
 * 新增一個 behavior：在 app/frontend/behaviors/ 建檔並 `export function init`，
 * 然後在下面的 REGISTRY 加一行。不需要動 layout。
 */

export interface Behavior {
  init: (root: HTMLElement) => void;
}

type Loader = () => Promise<Behavior>;

const REGISTRY: Record<string, Loader> = {
  "admin-user-activity": () => import("../behaviors/adminUserActivity"),
  "admin-user-export": () => import("../behaviors/adminUserExport"),
  "alert-list": () => import("../behaviors/alertList"),
  "app-switcher": () => import("../behaviors/appSwitcher"),
  "bull-call-spreads": () => import("../behaviors/bullCallSpreads"),
  "bull-call-tooltips": () => import("../behaviors/bullCallTooltips"),
  "bull-put-spreads": () => import("../behaviors/bullPutSpreads"),
  "bull-put-tooltips": () => import("../behaviors/bullPutTooltips"),
  "font-size-controls": () => import("../behaviors/fontSizeControls"),
  "iv-analysis": () => import("../behaviors/ivAnalysis"),
  "iv-education-chain-tooltip": () => import("../behaviors/ivEducationChainTooltip"),
  "iv-education-chart": () => import("../behaviors/ivEducationChart"),
  "iv-education-tts": () => import("../behaviors/ivEducationTts"),
  "iv-watchlists": () => import("../behaviors/ivWatchlists"),
  "leaps-loading": () => import("../behaviors/leapsLoading"),
  "methodology-note-toggle": () => import("../behaviors/methodologyNoteToggle"),
  "momentum-analysis-panel": () => import("../behaviors/momentumAnalysisPanel"),
  "momentum-news-tabs": () => import("../behaviors/momentumNewsTabs"),
  "momentum-watchlist-manager": () => import("../behaviors/momentumWatchlistManager"),
  "ownership-panel": () => import("../behaviors/ownershipPanel"),
  "portfolio-holdings": () => import("../behaviors/portfolioHoldings"),
  "tech-dash-dte-filter": () => import("../behaviors/techDashDteFilter"),
  "tech-dash-loading": () => import("../behaviors/techDashLoading"),
  "tech-dash-max-pain-filter": () => import("../behaviors/techDashMaxPainFilter"),
  "tech-dash-options-charts": () => import("../behaviors/techDashOptionsCharts"),
  "ticker-search": () => import("../behaviors/tickerSearch"),
};

function mount(el: HTMLElement): void {
  const name = el.dataset["behavior"];
  if (!name) return;

  const load = REGISTRY[name];
  if (!load) {
    console.warn(`[behaviors] 找不到已註冊的 behavior：${name}`);
    return;
  }

  load()
    .then((mod) => mod.init(el))
    .catch((err: unknown) => {
      // 單一 behavior 掛掉不該讓同一頁其他行為跟著失效。
      console.error(`[behaviors] ${name} 載入失敗`, err);
    });
}

// entrypoint 以 type="module" 載入，本身就是 deferred，執行時 DOM 已經解析完成。
// 這比原本內嵌在 body 中段、靠位置碰運氣的寫法更可靠。
document.querySelectorAll<HTMLElement>("[data-behavior]").forEach(mount);
