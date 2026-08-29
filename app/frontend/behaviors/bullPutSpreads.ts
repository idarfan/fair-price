/**
 * Bull Put Spread 頁：到期日/期權鏈抓取、輪詢、波動率、試算。
 *
 * 稽核 H-3 Wave 3：原本內嵌在 app/components/bull_put_spreads/page_component.rb 的 heredoc 裡。
 * 原本用 Ruby 插值寫進來的路由與狀態，改成掛載元素上的 data-config
 * JSON（用 JSON 而不是逐個 data attribute，是為了保留 null 與數值型別，
 * dataset 只能給字串，會把 nil 變成空字串而改變 truthiness）。
 * 與 Bull Call 共用的小工具已抽到 shared/spreadHelpers（稽核 M-6）。
 */

import { createSpreadHelpers } from "./shared/spreadHelpers";
import { isRecord, num, str } from "./shared/json";

interface Routes {
  index: string;
  status: string;
  fetchExpirations: string;
  fetchChain: string;
  calculate: string;
  volatility: string;
}

interface Config {
  symbol: string;
  expiration: string;
  routes: Routes;
}

function parseConfig(raw: string | undefined): Config | null {
  if (!raw) return null;
  let parsed: unknown;
  try { parsed = JSON.parse(raw); } catch { return null; }
  if (!isRecord(parsed)) return null;
  const r = parsed["routes"];
  if (!isRecord(r)) return null;
  const route = (key: string): string => str(r, key) ?? "";
  return {
    symbol: str(parsed, "symbol") ?? "",
    expiration: str(parsed, "expiration") ?? "",
    routes: {
      index: route("index"),
      status: route("status"),
      fetchExpirations: route("fetchExpirations"),
      fetchChain: route("fetchChain"),
      calculate: route("calculate"),
      volatility: route("volatility"),
    },
  };
}

// 跟 Ruby 端 COLUMNS 常數(app/components/bull_put_spreads/page_component.rb)
// 保持同一份欄位清單——表格 data-* 屬性、選腳明細列的 data-field，都用這份
// key 對應，避免兩處各自維護漂移。
const COLUMN_KEYS = [
  "strike", "moneyness", "bid", "mid", "ask", "last",
  "change", "pct_change", "volume", "open_interest", "oi_change", "iv", "delta",
] as const;

type ColumnKey = typeof COLUMN_KEYS[number];

/** 每一列的欄位值；讀不到的欄位是 NaN（與型別化前的 parseFloat 行為一致）。 */
type RowData = Record<ColumnKey, number>;

interface SelectedLeg extends RowData {
  row: HTMLElement;
}

interface Volatility {
  status: string | undefined;
  iv: number | undefined;
  hv: number | undefined;
  iv_rank: number | undefined;
}

export function init(root: HTMLElement): void {
  const parsed = parseConfig(root.dataset["config"]);
  if (!parsed) return;
  // 明確型別的 const：narrowing 在巢狀 function declaration 裡不保證留存。
  const CFG: Config = parsed;

  const H = createSpreadHelpers({ prefix: "bpus", statusPath: CFG.routes.status });
  const { csrf, pollJob, showProgress, fmt, fmtLots, currentLots } = H;

  // ── Step1: 送出代號 → 抓履約日 ──────────────────────────────────────
  const form = document.getElementById("bpus-symbol-form");
  const inpEl = document.getElementById("bpus-symbol-input");
  const inp = inpEl instanceof HTMLInputElement ? inpEl : null;
  inp?.addEventListener("input", () => { inp.value = inp.value.toUpperCase(); });

  function fetchExpirations(symbol: string): void {
    document.getElementById("bpus-loading")?.classList.remove("hidden");
    showProgress();
    const submitBtn = document.getElementById("bpus-submit-btn");
    const retryBtnEl = document.getElementById("bpus-fetch-expirations-btn");
    if (submitBtn instanceof HTMLButtonElement) submitBtn.disabled = true;
    if (retryBtnEl instanceof HTMLButtonElement) retryBtnEl.disabled = true;
    fetch(CFG.routes.fetchExpirations, {
      method: "POST",
      headers: { "Content-Type": "application/json", "X-CSRF-Token": csrf() },
      body: JSON.stringify({ symbol }),
    })
      .then((r) => r.json())
      .then((d: unknown) => {
        const status = str(d, "status");
        const jobId = str(d, "job_id");
        const base = `${CFG.routes.index}?symbol=${symbol}`;
        if (status === "ready") {
          window.location.href = base;
        } else if (status === "cdp_offline") {
          window.location.href = `${base}&job_status=cdp_offline`;
        } else if (jobId) {
          pollJob(jobId, (s) => { window.location.href = `${base}&job_status=${s}`; });
        } else {
          window.location.href = `${base}&job_status=error`;
        }
      }).catch(() => {
        window.location.href = `${CFG.routes.index}?symbol=${symbol}&job_status=error`;
      });
  }

  form?.addEventListener("submit", (e) => {
    e.preventDefault();
    const symbol = inp ? inp.value.trim().toUpperCase() : "";
    if (!symbol) return;
    fetchExpirations(symbol);
  });

  document.getElementById("bpus-fetch-expirations-btn")
    ?.addEventListener("click", () => { fetchExpirations(CFG.symbol); });

  // ── Step2: 點履約日 → 抓 Put 鏈 ──────────────────────────────────────
  document.querySelectorAll<HTMLElement>("[data-bpus-expiration-btn]").forEach((btn) => {
    btn.addEventListener("click", () => {
      const exp = btn.getAttribute("data-exp") ?? "";
      const symbol = CFG.symbol;
      showProgress();
      document.querySelectorAll("[data-bpus-expiration-btn]").forEach((b) => {
        if (b instanceof HTMLButtonElement) b.disabled = true;
      });
      fetch(CFG.routes.fetchChain, {
        method: "POST",
        headers: { "Content-Type": "application/json", "X-CSRF-Token": csrf() },
        body: JSON.stringify({ symbol, expiration: exp }),
      })
        .then((r) => r.json())
        .then((d: unknown) => {
          const base = `${CFG.routes.index}?symbol=${symbol}&expiration=${encodeURIComponent(exp)}`;
          const status = str(d, "status");
          const jobId = str(d, "job_id");
          if (status === "ready") {
            window.location.href = base;
          } else if (status === "cdp_offline") {
            window.location.href = `${base}&chain_job_status=cdp_offline`;
          } else if (jobId) {
            pollJob(jobId, (s) => { window.location.href = `${base}&chain_job_status=${s}`; });
          } else {
            window.location.href = `${base}&chain_job_status=error`;
          }
        }).catch(() => {
          window.location.href =
            `${CFG.routes.index}?symbol=${symbol}&expiration=${encodeURIComponent(exp)}&chain_job_status=error`;
        });
    });
  });

  // ── Step3/4: 選腳互動 ────────────────────────────────────────────────
  const state: { protection: SelectedLeg | null; csp: SelectedLeg | null } = {
    protection: null, csp: null,
  };

  // 用 !important 變體(!bg-blue-50 等)蓋過列本身的斑馬紋 bg-gray-50/50——
  // 兩者都是同層級 utility class，DOM classList 加入順序不影響 CSS
  // cascade，實測發現奇數列(有斑馬紋)加了 bg-red-50/bg-blue-50 仍被斑馬紋
  // 蓋掉、完全看不到標色(bpus-fix.md 項目3)。!important 變體確保一定蓋過。
  function clearHighlight(row: HTMLElement): void {
    row.classList.remove("!bg-blue-50", "!border-blue-400", "!bg-red-50", "!border-red-400", "bpus-selected");
  }

  function setPhase(phase: string): void {
    const table = document.getElementById("bpus-chain-table");
    if (!table) return;
    table.classList.toggle("bpus-phase-protection", phase === "protection");
    table.classList.toggle("bpus-phase-csp", phase === "csp");
  }

  // kind 為 null 時兩個分頁都恢復未選取樣式。
  function setActiveTab(kind: string | null): void {
    document.querySelectorAll("[data-bpus-recommend-tab]").forEach((btn) => {
      const active = btn.getAttribute("data-bpus-recommend-tab") === kind;
      btn.classList.toggle("bg-blue-600", active);
      btn.classList.toggle("text-white", active);
      btn.classList.toggle("border-blue-600", active);
      btn.classList.toggle("bg-white", !active);
      btn.classList.toggle("text-gray-700", !active);
      btn.classList.toggle("border-gray-300", !active);
    });
  }

  function hideRecommendExplain(): void {
    const el = document.getElementById("bpus-recommend-explain");
    if (el) { el.classList.add("hidden"); el.textContent = ""; }
    const volEl = document.getElementById("bpus-volatility-explain");
    if (volEl) { volEl.classList.add("hidden"); volEl.textContent = ""; }
    activeRecommendKind = null;
    setActiveTab(null);
  }

  // ── 波動率背景資料(bpus-fix.md 項目6)：頁面載入後背景輪詢，抓到才顯示，
  // 不阻塞履約日/Put 鏈這條主流程；抓不到就靜靜維持隱藏，不報錯打擾使用者。
  let lastVolatility: Volatility | null = null;
  let activeRecommendKind: string | null = null;

  function renderVolatilityExplain(): void {
    const volEl = document.getElementById("bpus-volatility-explain");
    const v = lastVolatility;
    if (!volEl || !activeRecommendKind || !v || v.status !== "success") return;
    if (v.iv === undefined) return;
    const levelNote = v.iv >= 80
      ? "IV 偏高：權利金較厚、ROC 較有吸引力，但要留意財報後或事件後的 IV crush 侵蝕權利金價值。"
      : (v.iv <= 40
        ? "IV 偏低：權利金較薄，同樣寬度的價差 ROC 會偏低，賣方吸引力較弱。"
        : "IV 中等：權利金與 ROC 落在一般水準。");
    const rankNote = (typeof v.iv_rank === "number")
      ? `目前 IV Rank ${v.iv_rank.toFixed(1)}%（相對自身歷史的百分位）`
        + (v.iv_rank >= 50 ? "，處於相對高檔，賣方（收租）策略相對有利。" : "，處於相對低檔，賣方拿到的權利金相對單薄。")
      : "";
    const kindLabel = activeRecommendKind === "conservative" ? "保守收租" : "激進收租";
    volEl.classList.remove("hidden");
    volEl.textContent = `📊 ${kindLabel} × 目前波動率：IV ${fmt(v.iv)}%、HV ${fmt(v.hv)}%。${levelNote}${rankNote}`;
  }

  function fetchVolatility(symbol: string, expiration: string): void {
    fetch(`${CFG.routes.volatility}?symbol=${encodeURIComponent(symbol)}&expiration=${encodeURIComponent(expiration)}`)
      .then((r) => r.json())
      .then((d: unknown) => {
        if (str(d, "status") === "pending") {
          setTimeout(() => { fetchVolatility(symbol, expiration); }, 4000);
        } else {
          lastVolatility = {
            status: str(d, "status"),
            iv: num(d, "iv"),
            hv: num(d, "hv"),
            iv_rank: num(d, "iv_rank"),
          };
          renderVolatilityExplain();
        }
      }).catch(() => {});
  }

  if (document.getElementById("bpus-chain-table") && CFG.expiration) {
    fetchVolatility(CFG.symbol, CFG.expiration);
  }

  function resetSelection(): void {
    state.protection = null;
    state.csp = null;
    document.querySelectorAll<HTMLElement>("[data-bpus-row]").forEach((row) => {
      clearHighlight(row);
      row.classList.remove("opacity-40", "pointer-events-none");
      // 無報價列的禁用狀態由後端 render 決定，這裡不動。
    });
    setPhase("protection");
    hideRecommendExplain();
    document.getElementById("bpus-calc-panel")?.classList.add("hidden");
    document.getElementById("bpus-selected-legs")?.classList.add("hidden");
    ["bpus-protection-row", "bpus-csp-row"].forEach((id) => {
      document.getElementById(id)?.classList.add("hidden");
    });
  }

  function attrName(key: string): string { return `data-${key.replace(/_/g, "-")}`; }

  function rowData(row: HTMLElement): RowData {
    const d = {} as RowData;
    COLUMN_KEYS.forEach((k) => { d[k] = parseFloat(row.getAttribute(attrName(k)) ?? ""); });
    return d;
  }

  function fmtField(key: ColumnKey, v: number): string {
    const isDelta = (key === "change" || key === "pct_change" || key === "oi_change");
    if (isNaN(v)) return isDelta ? "unch" : "—";
    if (isDelta && v === 0) return "unch";
    switch (key) {
      case "strike": case "bid": case "mid": case "ask": case "last":
        return v.toFixed(2);
      case "moneyness":
        return `${(v * 100).toFixed(2)}%`;
      case "iv":
        return `${(v * 100).toFixed(1)}%`;
      case "delta":
        return v.toFixed(2);
      case "change":
        return `${v >= 0 ? "+" : ""}${v.toFixed(2)}`;
      case "pct_change":
        return `${v >= 0 ? "+" : ""}${(v * 100).toFixed(2)}%`;
      case "oi_change":
        return `${v >= 0 ? "+" : ""}${v}`;
      default:
        return String(v);
    }
  }

  // 完整呈現讀到的 Barchart 原始資料（不重算、不篩選欄位），選一腳就立刻長一排。
  function fillLegRow(rowId: string, data: RowData): void {
    const row = document.getElementById(rowId);
    if (!row) return;
    document.getElementById("bpus-selected-legs")?.classList.remove("hidden");
    row.classList.remove("hidden");
    COLUMN_KEYS.forEach((k) => {
      const cell = row.querySelector(`[data-field="${k}"]`);
      if (cell) cell.textContent = fmtField(k, data[k]);
    });
  }

  // 保守/激進收租建議：從已渲染的表格挑兩腳，不用額外打後端。
  // CSP 腳挑 |delta| 最接近目標值的 strike；保護腳挑其下一個「有真實
  // 報價」的 strike（維持窄價差，沿用注意事項§5「三級的甜蜜點在窄價
  // 差」）。iv/volume/oi 同時為 0 的列視為無真實報價的殘影資料，排除。
  const RECOMMEND_TARGETS: Record<string, number> = { conservative: 0.15, aggressive: 0.30 };

  interface CandidateRow { el: HTMLElement; data: RowData }

  function isRealQuoteRow(d: RowData): boolean {
    const hasQuote = !isNaN(d.bid) || !isNaN(d.ask);
    const isGhost = d.iv === 0 && d.volume === 0 && d.open_interest === 0;
    return hasQuote && !isGhost;
  }

  function collectValidRows(): CandidateRow[] {
    return [...document.querySelectorAll<HTMLElement>("[data-bpus-row]")]
      .map((r) => ({ el: r, data: rowData(r) }))
      .filter((x) => isRealQuoteRow(x.data))
      .sort((a, b) => a.data.strike - b.data.strike);
  }

  function findRecommendation(targetAbsDelta: number): { protection: CandidateRow; short: CandidateRow } | null {
    const rows = collectValidRows();
    // 用 for...of 而不是 forEach：在 callback 裡賦值時，TS 看不到那次賦值，
    // 會把 shortCandidate 窄化成 never，後面取 .data 就編不過。
    let short: CandidateRow | null = null;
    let shortDiff = Infinity;
    for (const r of rows) {
      if (isNaN(r.data.delta)) continue;
      const diff = Math.abs(Math.abs(r.data.delta) - targetAbsDelta);
      if (diff < shortDiff) { shortDiff = diff; short = r; }
    }
    if (!short) return null;

    const lower = rows.filter((r) => r.data.strike < short.data.strike);
    const protectionCandidate = lower[lower.length - 1]; // 最接近的下一個 strike = 最窄價差
    if (!protectionCandidate) return null;

    return { protection: protectionCandidate, short };
  }

  function applyRecommendation(kind: string): void {
    resetSelection();
    const target = RECOMMEND_TARGETS[kind];
    const rec = target === undefined ? null : findRecommendation(target);
    const explainEl = document.getElementById("bpus-recommend-explain");
    if (!rec) {
      if (explainEl) {
        explainEl.classList.remove("hidden");
        explainEl.textContent = "此履約日的期權鏈找不到符合條件的建議組合（報價或 Delta 資料不足），請手動選腳。";
      }
      return;
    }
    setActiveTab(kind);

    const pRow = rec.protection.el;
    const pData = rec.protection.data;
    state.protection = { row: pRow, ...pData };
    clearHighlight(pRow);
    pRow.classList.add("!bg-blue-50", "!border-blue-400", "bpus-selected");
    fillLegRow("bpus-protection-row", pData);
    setPhase("csp");
    document.querySelectorAll<HTMLElement>("[data-bpus-row]").forEach((r) => {
      const rd = rowData(r);
      if (r !== pRow && rd.strike <= pData.strike) r.classList.add("opacity-40", "pointer-events-none");
    });

    const sRow = rec.short.el;
    const sData = rec.short.data;
    state.csp = { row: sRow, ...sData };
    clearHighlight(sRow);
    sRow.classList.add("!bg-red-50", "!border-red-400", "bpus-selected");
    fillLegRow("bpus-csp-row", sData);
    runCalculate();

    if (explainEl) {
      const label = kind === "conservative" ? "保守收租" : "激進收租";
      const targetLabel = kind === "conservative" ? "-0.15" : "-0.30";
      const profile = kind === "conservative"
        ? "較遠價外、勝率較高但權利金較低，適合重視安全邊際的收租策略。"
        : "較接近價平、權利金較高但勝率較低、被指派機率較高，適合追求更高 ROC 的積極策略。";
      explainEl.classList.remove("hidden");
      explainEl.textContent = `${label}建議：CSP 腳選 |Delta| 最接近 ${targetLabel} 的履約價 $`
        + `${fmt(sData.strike)}（實際 Delta ${sData.delta.toFixed(2)}），保護腳取其下一個有報價的履約價 $`
        + `${fmt(pData.strike)}，維持窄價差以降低押金；${profile}`;
    }

    activeRecommendKind = kind;
    renderVolatilityExplain();
  }

  document.querySelectorAll("[data-bpus-recommend-tab]").forEach((btn) => {
    btn.addEventListener("click", () => {
      const kind = btn.getAttribute("data-bpus-recommend-tab");
      if (kind) applyRecommendation(kind);
    });
  });

  // 口數：金額類結果用「單口 × 口數 = 總計」呈現；BE/ROC/風險報酬比是
  // 比率，不隨口數變化，維持單口顯示(bpus-fix.md 項目5)。
  let lastCalcResult: unknown = null;

  function runCalculate(): void {
    const csp = state.csp;
    const protection = state.protection;
    if (!csp || !protection) return;
    const payload = {
      short_strike: csp.strike, short_bid: csp.bid,
      long_strike: protection.strike, long_ask: protection.ask,
    };
    fetch(CFG.routes.calculate, {
      method: "POST",
      headers: { "Content-Type": "application/json", "X-CSRF-Token": csrf() },
      body: JSON.stringify(payload),
    })
      .then((r) => r.json())
      .then((d: unknown) => {
        lastCalcResult = d;
        renderCalcResult(d);
        window.FairPriceTrack?.command("bpus_calculate", payload);
      })
      .catch(() => {});
  }

  document.getElementById("bpus-lots-input")?.addEventListener("input", () => {
    if (lastCalcResult) renderCalcResult(lastCalcResult);
  });

  function renderCalcResult(d: unknown): void {
    const panel = document.getElementById("bpus-calc-panel");
    const grid = document.getElementById("bpus-calc-grid");
    const warn = document.getElementById("bpus-calc-warning");
    const scen = document.getElementById("bpus-scenario");
    if (!panel || !grid) return;
    panel.classList.remove("hidden");

    const warning = str(d, "warning");
    if (warn) {
      if (warning === "debit") {
        warn.textContent = "⚠️ 此組合為 debit，非收租結構";
        warn.classList.remove("hidden");
      } else if (warning === "invalid_width") {
        warn.textContent = "⚠️ CSP 腳的履約價必須高於保護腳";
        warn.classList.remove("hidden");
      } else {
        warn.classList.add("hidden");
      }
    }

    const lots = currentLots();
    const shortStrike = num(d, "short_strike");
    const netCredit = num(d, "net_credit");

    // 提前指派所需現金：CSP 履約價 × 100 × 口數；括號附註扣除已收
    // 權利金(net_credit，已隨口數放大)後的淨成本(bpus-fix.md 項目4)。
    let assignCashHtml = "—";
    if (warning !== "invalid_width" && shortStrike !== undefined) {
      const cashTotal = shortStrike * 100 * lots;
      const netCreditTotal = (netCredit ?? 0) * lots;
      const netCost = cashTotal - netCreditTotal;
      assignCashHtml = `$${fmt(cashTotal)}（淨成本 $${fmt(netCost)}）`;
    }

    const roc = num(d, "roc");
    const riskReward = num(d, "risk_reward");

    grid.innerHTML =
      `<div><dt class="text-[24px] text-gray-500">淨權利金收入</dt><dd class="font-semibold">${fmtLots(netCredit, lots)}</dd></div>`
      + `<div><dt class="text-[24px] text-gray-500">價差寬度</dt><dd class="font-semibold">${fmt(num(d, "width"))}</dd></div>`
      + `<div><dt class="text-[24px] text-gray-500">最大獲利</dt><dd class="font-semibold text-green-700">${fmtLots(num(d, "max_profit"), lots)}</dd></div>`
      + `<div><dt class="text-[24px] text-gray-500">最大虧損</dt><dd class="font-semibold text-red-700">${fmtLots(num(d, "max_loss"), lots)}</dd></div>`
      + `<div><dt class="text-[24px] text-gray-500">押金</dt><dd class="font-semibold text-red-700">${fmtLots(num(d, "margin"), lots)}</dd></div>`
      + `<div><dt class="text-[24px] text-gray-500">損益平衡點</dt><dd class="font-semibold">$${fmt(num(d, "breakeven"))}</dd></div>`
      + `<div><dt class="text-[24px] text-gray-500">ROC</dt><dd class="font-semibold text-yellow-700">${roc === undefined ? "—" : `${roc}%`}</dd></div>`
      + `<div><dt class="text-[24px] text-gray-500">風險報酬比</dt><dd class="font-semibold">${riskReward === undefined ? "—" : `1 : ${riskReward}`}</dd></div>`
      + `<div><dt class="text-[24px] text-gray-500">提前指派：承接現金</dt><dd class="font-semibold text-purple-700">${assignCashHtml}</dd></div>`;

    if (!scen) return;
    if (warning !== "invalid_width") {
      scen.innerHTML =
        `<p>🌞 股價 ≥ $${fmt(shortStrike)}：全額獲利 = ${fmtLots(netCredit, lots)}</p>`
        + `<p>🧊 股價介於 $${fmt(num(d, "long_strike"))} ~ $${fmt(num(d, "breakeven"))}：開始賠錢</p>`
        + `<p>🥶 股價 ≤ $${fmt(num(d, "long_strike"))}：最大虧損鎖定 = ${fmtLots(num(d, "max_loss"), lots)}</p>`;
    } else {
      scen.innerHTML = "";
    }
  }

  document.querySelectorAll<HTMLElement>("[data-bpus-row]").forEach((row) => {
    row.addEventListener("click", () => {
      const data = rowData(row);

      if (state.protection && row === state.protection.row) {
        resetSelection();
        return;
      }

      if (!state.protection) {
        state.protection = { row, ...data };
        clearHighlight(row);
        row.classList.add("!bg-blue-50", "!border-blue-400", "bpus-selected");
        fillLegRow("bpus-protection-row", data);
        setPhase("csp");
        document.querySelectorAll<HTMLElement>("[data-bpus-row]").forEach((r) => {
          const rd = rowData(r);
          if (r !== row && rd.strike <= data.strike) {
            r.classList.add("opacity-40", "pointer-events-none");
          }
        });
        return;
      }

      if (!state.csp && data.strike > state.protection.strike) {
        state.csp = { row, ...data };
        clearHighlight(row);
        row.classList.add("!bg-red-50", "!border-red-400", "bpus-selected");
        fillLegRow("bpus-csp-row", data);
        runCalculate();
      }
    });
  });

  document.getElementById("bpus-reset-legs")?.addEventListener("click", (e) => {
    e.preventDefault();
    resetSelection();
  });
}
