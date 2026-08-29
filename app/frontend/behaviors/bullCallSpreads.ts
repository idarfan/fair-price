/**
 * Bull Call Spread 頁：到期日/期權鏈抓取、輪詢、推薦、試算。
 *
 * 稽核 H-3 Wave 3：原本內嵌在 app/components/bull_call_spreads/page_component.rb 的 heredoc 裡。
 * 原本用 Ruby 插值寫進來的路由與狀態，改成掛載元素上的 data-config
 * JSON（用 JSON 而不是逐個 data attribute，是為了保留 null 與數值型別，
 * dataset 只能給字串，會把 nil 變成空字串而改變 truthiness）。
 * 與 Bull Put 共用的小工具已抽到 shared/spreadHelpers（稽核 M-6）。
 */

import { createSpreadHelpers } from "./shared/spreadHelpers";
import { isRecord, num, str } from "./shared/json";

interface Routes {
  index: string;
  status: string;
  fetchExpirations: string;
  fetchChain: string;
  recommend: string;
  calculate: string;
}

interface Config {
  symbol: string;
  expiration: string;
  underlyingPrice: number | undefined;
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
    underlyingPrice: num(parsed, "underlyingPrice"),
    routes: {
      index: route("index"),
      status: route("status"),
      fetchExpirations: route("fetchExpirations"),
      fetchChain: route("fetchChain"),
      recommend: route("recommend"),
      calculate: route("calculate"),
    },
  };
}

/** 後端 /bcvs/recommend 回傳的每個分頁。缺值一律 undefined，不替它猜。 */
interface Tab {
  k1: number | undefined;
  k2: number | undefined;
  debit: number | undefined;
  debit_mid: number | undefined;
  cost_per_contract: number | undefined;
  max_profit: number | undefined;
  max_loss: number | undefined;
  breakeven: number | undefined;
  risk_reward: number | undefined;
  warning: string | undefined;
  naked_cost: number | undefined;
  naked_breakeven: number | undefined;
  s_star: number | undefined;
  closeout_value: number | undefined;
  spread_max_value: number | undefined;
  closeout_profit: number | undefined;
  realized_pct: number | undefined;
}

function parseTab(raw: unknown): Tab | null {
  if (!isRecord(raw)) return null;
  return {
    k1: num(raw, "k1"), k2: num(raw, "k2"),
    debit: num(raw, "debit"), debit_mid: num(raw, "debit_mid"),
    cost_per_contract: num(raw, "cost_per_contract"),
    max_profit: num(raw, "max_profit"), max_loss: num(raw, "max_loss"),
    breakeven: num(raw, "breakeven"), risk_reward: num(raw, "risk_reward"),
    warning: str(raw, "warning"),
    naked_cost: num(raw, "naked_cost"), naked_breakeven: num(raw, "naked_breakeven"),
    s_star: num(raw, "s_star"),
    closeout_value: num(raw, "closeout_value"),
    spread_max_value: num(raw, "spread_max_value"),
    closeout_profit: num(raw, "closeout_profit"),
    realized_pct: num(raw, "realized_pct"),
  };
}

/** 兩個可能缺值的數字相減；任一缺就回 undefined（fmt 會顯示「—」）。 */
function sub(a: number | undefined, b: number | undefined): number | undefined {
  return (a === undefined || b === undefined) ? undefined : a - b;
}

export function init(root: HTMLElement): void {
  const parsed = parseConfig(root.dataset["config"]);
  if (!parsed) return;
  // 明確型別的 const：narrowing 在巢狀 function declaration 裡不保證留存。
  const CFG: Config = parsed;

  const H = createSpreadHelpers({ prefix: "bcvs", statusPath: CFG.routes.status });
  const { csrf, pollJob, showProgress, fmt, fmtLots, currentLots } = H;

  // 與 Ruby #strike_row_id 用同一種格式化方式組 row id，避免 Float#to_s
  // 與 JS Number 序列化不一致造成兩端 id 對不上。
  function strikeRowId(strike: unknown): string {
    return `bcvs-row-${Number(strike).toFixed(2).replace(".", "_")}`;
  }

  const CURRENT_PRICE = CFG.underlyingPrice;

  // ── Step1: 送出代號 → 抓到期日 ──────────────────────────────────────
  const form = document.getElementById("bcvs-symbol-form");
  const inpEl = document.getElementById("bcvs-symbol-input");
  const inp = inpEl instanceof HTMLInputElement ? inpEl : null;
  inp?.addEventListener("input", () => { inp.value = inp.value.toUpperCase(); });

  function fetchExpirations(symbol: string): void {
    document.getElementById("bcvs-loading")?.classList.remove("hidden");
    showProgress();
    const submitBtn = document.getElementById("bcvs-submit-btn");
    const retryBtnEl = document.getElementById("bcvs-fetch-expirations-btn");
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

  document.getElementById("bcvs-fetch-expirations-btn")
    ?.addEventListener("click", () => { fetchExpirations(CFG.symbol); });

  // ── Step2: 點到期日 → 抓 Call 鏈 ─────────────────────────────────────
  document.querySelectorAll<HTMLElement>("[data-bcvs-expiration-btn]").forEach((btn) => {
    btn.addEventListener("click", () => {
      const exp = btn.getAttribute("data-exp") ?? "";
      const symbol = CFG.symbol;
      showProgress();
      document.querySelectorAll("[data-bcvs-expiration-btn]").forEach((b) => {
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

  // ── Step3/4: K1 下拉 → 三 tab K2 建議 ────────────────────────────────
  let lastTabs: Record<string, Tab | null> | null = null;
  let activeTab = "balanced";

  function setActiveTab(kind: string): void {
    activeTab = kind;
    document.querySelectorAll("[data-bcvs-recommend-tab]").forEach((btn) => {
      const active = btn.getAttribute("data-bcvs-recommend-tab") === kind;
      btn.classList.toggle("bg-blue-600", active);
      btn.classList.toggle("text-white", active);
      btn.classList.toggle("border-blue-600", active);
      btn.classList.toggle("bg-white", !active);
      btn.classList.toggle("text-gray-700", !active);
      btn.classList.toggle("border-gray-300", !active);
    });
    renderTab();
  }

  function highlightK1K2(k1: unknown, k2: unknown): void {
    document.querySelectorAll("#bcvs-chain-table tr").forEach((r) => {
      r.classList.remove("!bg-blue-50", "!bg-red-50");
    });
    document.getElementById(strikeRowId(k1))?.classList.add("!bg-blue-50");
    document.getElementById(strikeRowId(k2))?.classList.add("!bg-red-50");
  }

  function k1SelectValue(): string {
    const sel = document.getElementById("bcvs-k1-select");
    return sel instanceof HTMLSelectElement ? sel.value : "";
  }

  function renderTab(): void {
    const grid = document.getElementById("bcvs-calc-grid");
    const warn = document.getElementById("bcvs-calc-warning");
    const errEl = document.getElementById("bcvs-recommend-error");
    if (!grid || !lastTabs) return;

    const tab = lastTabs[activeTab];
    if (!tab) {
      grid.innerHTML = "";
      if (errEl) {
        errEl.classList.remove("hidden");
        errEl.textContent = "此分頁找不到合適的 K2 候選（可能候選 strike 不足）。";
      }
      return;
    }
    if (errEl) errEl.classList.add("hidden");

    highlightK1K2(tab.k2 === undefined ? null : k1SelectValue(), tab.k2);

    if (warn) {
      if (tab.warning === "invalid_width") {
        warn.textContent = "⚠️ K2 必須高於 K1";
        warn.classList.remove("hidden");
      } else if (tab.warning === "non_debit") {
        warn.textContent = "⚠️ 此組合淨成本非正值，報價可能異常";
        warn.classList.remove("hidden");
      } else {
        warn.classList.add("hidden");
      }
    }

    const lots = currentLots();
    // bcvs.md §策略定義／§功能流程 步驟3：淨成本 debit（每股，另示 mid
    // 供參）與每口成本（×100×口數）是規格明列的兩個獨立欄位，不可合併
    // 只顯示其中一個。
    const debitMidHtml = (typeof tab.debit_mid === "number") ? `（mid 版 $${fmt(tab.debit_mid)} 供參）` : "";
    // bcvs.md §字級鐵則 v4：Step 5 標籤 20px、主數字 24px 粗體。
    // K2 徽章（v4 待辦）：橘色邊框 #EF9F27 1.5px、圓角 8px、淡紅底
    // #FDE8E8、紅字 #A32D2D，內距 4px 12px，字級維持 24px 粗體。
    const k2Badge = `<span style="display:inline-block; border:1.5px solid #EF9F27; border-radius:8px; background:#FDE8E8; color:#A32D2D; padding:4px 12px; font-size:24px; font-weight:700;">$${fmt(tab.k2)}</span>`;
    grid.innerHTML =
      `<div><dt class="text-[20px] text-gray-500">K2</dt><dd class="mt-1">${k2Badge}</dd></div>`
      + `<div><dt class="text-[20px] text-gray-500">淨成本 debit</dt><dd class="text-[24px] font-bold">$${fmt(tab.debit)}<span class="text-[20px] font-normal">${debitMidHtml}</span></dd></div>`
      + `<div><dt class="text-[20px] text-gray-500">每口成本</dt><dd class="text-[24px] font-bold">${fmtLots(tab.cost_per_contract, lots)}</dd></div>`
      + `<div><dt class="text-[20px] text-gray-500">最大獲利</dt><dd class="text-[24px] font-bold text-green-700">${fmtLots(tab.max_profit, lots)}</dd></div>`
      + `<div><dt class="text-[20px] text-gray-500">最大損失</dt><dd class="text-[24px] font-bold text-red-700">${fmtLots(tab.max_loss, lots)}</dd></div>`
      + `<div><dt class="text-[20px] text-gray-500">損益兩平</dt><dd class="text-[24px] font-bold">$${fmt(tab.breakeven)}</dd></div>`
      + `<div><dt class="text-[20px] text-gray-500">報酬風險比</dt><dd class="text-[24px] font-bold text-yellow-700">${tab.risk_reward === undefined ? "—" : tab.risk_reward}</dd></div>`;

    renderIntervalTable(tab, lots);
    renderNakedComparison(tab, lots);
    renderEarlyClose(tab, lots);
    // basis 欄位保留使用者已輸入的值，不覆蓋；runRepairIfReady 自己會從
    // lastTabs[activeTab] 與鏈上那一列取 K2 / K2_bid。
    runRepairIfReady();
  }

  // ── 損益區間表（bcvs.md §損益區間表：動態，以實際數字渲染）───────────────
  // bcvs.md §視覺規範：損益區間表列色 — 虧損列紅字、損平列灰字、獲利列綠字。
  function renderIntervalTable(tab: Tab, lots: number): void {
    const el = document.getElementById("bcvs-interval-table");
    const exampleEl = document.getElementById("bcvs-interval-formula-example");
    if (!el || tab.warning === "invalid_width") {
      if (el) el.innerHTML = "";
      if (exampleEl) exampleEl.textContent = "";
      return;
    }

    if (exampleEl) {
      exampleEl.textContent = `本次範例：D = $${fmt(tab.debit)}（K1 $${fmt(tab.k1)} → K2 $${fmt(tab.k2)}）`;
    }

    const k1 = tab.k1;
    const k2 = tab.k2;
    const be = tab.breakeven;
    const maxLoss = tab.max_loss;
    const maxProfit = tab.max_profit;
    const price = CURRENT_PRICE;
    let exampleHtml = "";

    if (typeof price === "number" && k1 !== undefined && be !== undefined
        && tab.debit !== undefined && price > k1 && price < be) {
      const pnl = (price - k1 - tab.debit) * 100 * lots;
      exampleHtml = `（如以現價 $${fmt(price)} 到期 → ${pnl >= 0 ? "+" : ""}$${fmt(pnl)}）`;
    }
    let exampleHtml2 = "";
    if (typeof price === "number" && k1 !== undefined && be !== undefined && k2 !== undefined
        && tab.debit !== undefined && price >= be && price < k2) {
      const pnl2 = (price - k1 - tab.debit) * 100 * lots;
      exampleHtml2 = `（如以現價 $${fmt(price)} 到期 → +$${fmt(pnl2)}）`;
    }

    // bcvs.md §視覺規範 v3：損益區間表列色——虧損 #A32D2D、損平 #5F5E5A、
    // 獲利 #3B6D11，三欄（到期股價區間／結果／金額每口）。
    const rows = [
      { color: "#A32D2D", range: `≤ $${fmt(k1)}`, result: "賠掉全部成本", amount: `−${fmtLots(maxLoss, lots)}` },
      { color: "#A32D2D", range: `$${fmt(k1)} ~ $${fmt(be)}`, result: `部分虧損，隨股價遞減 ${exampleHtml}`, amount: "" },
      { color: "#5F5E5A", range: `= $${fmt(be)}`, result: "損益兩平", amount: "$0" },
      { color: "#3B6D11", range: `$${fmt(be)} ~ $${fmt(k2)}`, result: `開始獲利，隨股價遞增 ${exampleHtml2}`, amount: "" },
      { color: "#3B6D11", range: `≥ $${fmt(k2)}`, result: "最大獲利（封頂）", amount: `+${fmtLots(maxProfit, lots)}` },
    ];
    el.innerHTML =
      '<table class="bcvs-v3-table w-full"><thead><tr>'
      + '<th>到期股價區間</th><th>結果</th><th class="text-right">金額（每口）</th>'
      + "</tr></thead><tbody>"
      + rows.map((r) =>
        `<tr style="color:${r.color}"><td>${r.range}</td><td>${r.result}</td><td class="text-right">${r.amount}</td></tr>`,
      ).join("")
      + "</tbody></table>";
  }

  // ── 裸買 LEAPS 對照表（bcvs.md §為什麼不直接裸買）─────────────────────
  function renderNakedComparison(tab: Tab, lots: number): void {
    const el = document.getElementById("bcvs-naked-comparison");
    if (!el || tab.warning === "invalid_width") { if (el) el.innerHTML = ""; return; }

    let priceNote = "";
    if (typeof CURRENT_PRICE === "number" && typeof tab.s_star === "number") {
      priceNote = CURRENT_PRICE < tab.s_star
        ? `目前現價 $${fmt(CURRENT_PRICE)} 低於 S*，價差策略暫時領先。`
        : `目前現價 $${fmt(CURRENT_PRICE)} 高於 S*，裸買暫時領先。`;
    }

    el.innerHTML =
      '<table class="bcvs-v3-table w-full"><thead><tr>'
      + '<th>項目</th><th class="text-right">裸買 K1 Call</th><th class="text-right">價差（K1/K2）</th></tr></thead><tbody>'
      + `<tr><td>每口成本</td><td class="text-right">${fmtLots(tab.naked_cost, lots)}</td><td class="text-right">${fmtLots(tab.cost_per_contract, lots)}</td></tr>`
      + `<tr><td>最大損失</td><td class="text-right" style="color:#A32D2D">${fmtLots(tab.naked_cost, lots)}</td><td class="text-right" style="color:#3B6D11">${fmtLots(tab.max_loss, lots)}（金額小得多）</td></tr>`
      + `<tr><td>損益兩平</td><td class="text-right">$${fmt(tab.naked_breakeven)}</td><td class="text-right" style="color:#3B6D11">$${fmt(tab.breakeven)}（低得多）</td></tr>`
      + `<tr><td>最大獲利</td><td class="text-right" style="color:#3B6D11">無上限</td><td class="text-right">${fmtLots(tab.max_profit, lots)}（封頂）</td></tr>`
      + "</tbody></table>"
      + `<p class="mt-2" style="color:#5F5E5A; font-size:20px;">本次範例：S* = $${fmt(tab.k2)} + $${fmt(sub(tab.s_star, tab.k2))} = $${fmt(tab.s_star)}</p>`
      + `<p class="mt-1">${priceNote}</p>`;
  }

  // ── 提前平倉指引（bcvs.md §提前平倉指引）───────────────────────────────
  // bcvs.md §提前平倉指引：兩個口徑（毛額現值／淨額獲利）並列，嚴禁混用；
  // 上限也成對呈現（收回上限=(K2−K1)×100，獲利上限=收回上限−成本）。
  function renderEarlyClose(tab: Tab, lots: number): void {
    const el = document.getElementById("bcvs-early-close");
    if (!el || tab.warning === "invalid_width") { if (el) el.innerHTML = ""; return; }

    if (tab.closeout_value === undefined) {
      el.innerHTML = '<p style="color:#5F5E5A">需要 K1 現價 bid 才能估算平倉可收回金額。</p>';
      return;
    }

    const pct = tab.realized_pct;
    const suggestHtml = (typeof pct === "number" && pct >= 80)
      ? `<p class="font-semibold mt-2" style="color:#3B6D11">✅ 已實現 ${pct}%，達 80% 閾值，建議考慮獲利了結——剩餘部分要再抱數月，報酬/時間比會急遽變差，還多扛提前指派與回檔風險。</p>`
      : "";
    const profitColor = (typeof tab.closeout_profit === "number" && tab.closeout_profit >= 0)
      ? "#3B6D11" : "#A32D2D";

    el.innerHTML =
      `<p>現在平倉可收回（毛額） <strong>${fmtLots(tab.closeout_value, lots)}</strong>（收回上限 ${fmtLots(tab.spread_max_value, lots)}）</p>`
      + `<p>等於獲利（淨額，收回−成本） <strong style="color:${profitColor}">${fmtLots(tab.closeout_profit, lots)}</strong>（獲利上限 ${fmtLots(tab.max_profit, lots)}）</p>`
      + `<p>已實現獲利比例 Y = <strong>${typeof pct === "number" ? `${pct}%` : "—"}</strong></p>`
      + `<p class="mt-1" style="color:#5F5E5A; font-size:20px;">本次範例：Y = ($${fmt(tab.closeout_value)} − $${fmt(tab.cost_per_contract)}) ÷ $${fmt(tab.max_profit)} = ${typeof pct === "number" ? `${pct}%` : "—"}</p>`
      + suggestHtml
      + '<p class="mt-2" style="color:#5F5E5A">平倉一律組合單兩腳同出。</p>';
  }

  document.querySelectorAll("[data-bcvs-recommend-tab]").forEach((btn) => {
    btn.addEventListener("click", () => {
      const kind = btn.getAttribute("data-bcvs-recommend-tab");
      if (kind) setActiveTab(kind);
    });
  });

  document.getElementById("bcvs-lots-input")?.addEventListener("input", renderTab);

  function runRecommend(k1: number, k1Ask: number, k1Bid: number): void {
    const payload: Record<string, unknown> = {
      symbol: CFG.symbol, expiration: CFG.expiration, k1, k1_ask: k1Ask,
    };
    if (!isNaN(k1Bid)) payload["k1_bid"] = k1Bid;
    fetch(CFG.routes.recommend, {
      method: "POST",
      headers: { "Content-Type": "application/json", "X-CSRF-Token": csrf() },
      body: JSON.stringify(payload),
    })
      .then((r) => r.json())
      .then((d: unknown) => {
        const tabsEl = document.getElementById("bcvs-recommend-tabs");
        if (str(d, "error") !== undefined) {
          tabsEl?.classList.add("hidden");
          return;
        }
        const rawTabs = isRecord(d) ? d["tabs"] : undefined;
        if (!isRecord(rawTabs)) return;
        const parsed: Record<string, Tab | null> = {};
        for (const [key, value] of Object.entries(rawTabs)) parsed[key] = parseTab(value);
        lastTabs = parsed;
        tabsEl?.classList.remove("hidden");
        setActiveTab("balanced");
      }).catch(() => {});
  }

  const k1SelectEl = document.getElementById("bcvs-k1-select");
  if (k1SelectEl instanceof HTMLSelectElement) {
    k1SelectEl.addEventListener("change", () => {
      const opt = k1SelectEl.options[k1SelectEl.selectedIndex];
      if (!opt || !opt.value) return;
      runRecommend(
        parseFloat(opt.value),
        parseFloat(opt.getAttribute("data-ask") ?? ""),
        parseFloat(opt.getAttribute("data-bid") ?? ""),
      );
    });
    if (k1SelectEl.value) k1SelectEl.dispatchEvent(new Event("change"));
  }

  // ── 修復模式 ─────────────────────────────────────────────────────────
  function runRepairIfReady(): void {
    const basisEl = document.getElementById("bcvs-repair-basis-input");
    const currentBidEl = document.getElementById("bcvs-repair-current-bid-input");
    const resultEl = document.getElementById("bcvs-repair-result");
    if (!(basisEl instanceof HTMLInputElement) || !resultEl || !lastTabs) return;
    const basis = parseFloat(basisEl.value);
    if (isNaN(basis)) { resultEl.classList.add("hidden"); return; }

    const tab = lastTabs[activeTab];
    if (!tab || tab.k2 === undefined) return;
    const k1 = parseFloat(k1SelectValue());
    // k2_bid 理論上可以從 tab.debit 與下拉選單的 ask 回推，但最可靠的來源是
    // 這個 K2 實際渲染出來的鏈上那一列，所以直接讀它。
    const k2Row = document.getElementById(strikeRowId(tab.k2));
    const bidAttr = k2Row ? k2Row.getAttribute("data-bid") : null;
    if (bidAttr === null || bidAttr === "") return;
    const k2Bid = parseFloat(bidAttr);

    const payload: Record<string, unknown> = { k1, k2: tab.k2, k2_bid: k2Bid, basis };
    const currentBid = parseFloat(
      currentBidEl instanceof HTMLInputElement ? currentBidEl.value : "",
    );
    if (!isNaN(currentBid)) payload["k1_current_bid"] = currentBid;
    if (typeof CURRENT_PRICE === "number") payload["current_price"] = CURRENT_PRICE;

    fetch(CFG.routes.calculate, {
      method: "POST",
      headers: { "Content-Type": "application/json", "X-CSRF-Token": csrf() },
      body: JSON.stringify(payload),
    })
      .then((r) => r.json())
      .then((d: unknown) => {
        renderRepairResult(d);
        window.FairPriceTrack?.command("bcvs_calculate", payload);
      })
      .catch(() => {});
  }

  // bcvs.md §修復模式：三種到期情境（≤K1／中間／≥K2）與「對照現在直接
  // 平倉」並列顯示——中間情境是連續函數，只在現價落在 K1~K2 之間時
  // 後端才會回傳數字（否則為 null，不外推造值）。
  function renderRepairResult(d: unknown): void {
    const resultEl = document.getElementById("bcvs-repair-result");
    if (!resultEl) return;
    resultEl.classList.remove("hidden");

    const lockedTotal = num(d, "locked_result_total");
    const breakevenBasis = num(d, "breakeven_basis");
    let warningHtml = "";
    if (str(d, "warning") === "locked_loss") {
      const abs = lockedTotal === undefined ? undefined : Math.abs(lockedTotal);
      warningHtml = `<p class="text-red-700 font-semibold">⚠️ 此組合鎖定虧損 $${fmt(abs)}／口（basis 需 ≤ $${fmt(breakevenBasis)} 才不虧損）</p>`;
    }

    const midPnl = num(d, "mid_pnl_total");
    const midHtml = midPnl !== undefined
      ? `<p>中間情境（現價 $${fmt(CURRENT_PRICE)}）：$${fmt(midPnl)}／口</p>`
      : "";

    const closeoutPnl = num(d, "closeout_pnl");
    const closeoutHtml = closeoutPnl !== undefined
      ? `<p>對照現在直接平倉：收回 $${fmt(num(d, "closeout_proceeds"))}（損益 $${fmt(closeoutPnl)}）</p>`
      : "";

    resultEl.innerHTML =
      warningHtml
      + `<p>≤K1 情境：$${fmt(num(d, "below_k1_pnl_total"))}／口</p>`
      + midHtml
      + `<p>≥K2 鎖定結果：$${fmt(lockedTotal)}／口（分水嶺 basis = $${fmt(breakevenBasis)}）</p>`
      + closeoutHtml;
  }

  ["bcvs-repair-basis-input", "bcvs-repair-current-bid-input"].forEach((id) => {
    document.getElementById(id)?.addEventListener("input", runRepairIfReady);
  });
}
