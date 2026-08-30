/**
 * IV 分析頁：Call/Put 切換、到期日載入、查詢送出、結果渲染、觀察清單、儀表板。
 *
 * 稽核 H-3：原本內嵌在 app/components/iv_analysis/page_component.rb 的 heredoc 裡。
 */

import { applyDataStyles } from "./shared/dataStyles";
import { closestFrom, csrfToken } from "./shared/dom";
import { arr, isRecord, numeric, str } from "./shared/json";

// ── 後端回傳的形狀（只列這個檔案會碰到的欄位）────────────────────────────
interface WatchlistItem {
  ticker: string;
  latest_atm_iv: number | undefined;
  data_quality: string | undefined;
  last_fetched_at: string | undefined;
  intrinsic_value: number | undefined;
  time_value: number | undefined;
  is_live: boolean;
  query_label: string | undefined;
  option_type: string | undefined;
  strike: number | undefined;
  expiry_date: string | undefined;
  ivr_1y: number | undefined;
  ivp_1y: number | undefined;
  ivr_2y: number | undefined;
  ivp_2y: number | undefined;
  skew_rank: number | undefined;
  skew_pts: number | undefined;
  put_iv_025: number | undefined;
  call_iv_025: number | undefined;
  available_days: number | undefined;
  live_price: number | undefined;
  live_iv: number | undefined;
}

function parseItem(raw: unknown): WatchlistItem | null {
  if (!isRecord(raw)) return null;
  const ticker = str(raw, "ticker");
  if (ticker === undefined) return null;
  return {
    ticker,
    latest_atm_iv: numeric(raw, "latest_atm_iv"),
    data_quality: str(raw, "data_quality"),
    last_fetched_at: str(raw, "last_fetched_at"),
    intrinsic_value: numeric(raw, "intrinsic_value"),
    time_value: numeric(raw, "time_value"),
    is_live: raw["is_live"] === true,
    query_label: str(raw, "query_label"),
    option_type: str(raw, "option_type"),
    strike: numeric(raw, "strike"),
    expiry_date: str(raw, "expiry_date"),
    ivr_1y: numeric(raw, "ivr_1y"), ivp_1y: numeric(raw, "ivp_1y"),
    ivr_2y: numeric(raw, "ivr_2y"), ivp_2y: numeric(raw, "ivp_2y"),
    skew_rank: numeric(raw, "skew_rank"), skew_pts: numeric(raw, "skew_pts"),
    put_iv_025: numeric(raw, "put_iv_025"), call_iv_025: numeric(raw, "call_iv_025"),
    available_days: numeric(raw, "available_days"),
    live_price: numeric(raw, "live_price"), live_iv: numeric(raw, "live_iv"),
  };
}

const ACTIVE = "flex-1 py-2 bg-blue-600 text-white font-medium transition-colors";
const INACTIVE = "flex-1 py-2 bg-white text-gray-600 hover:bg-gray-50 font-medium transition-colors";

const BANNER_STYLES: Record<string, string> = {
  insufficient: "bg-yellow-50 border border-yellow-200 text-yellow-800",
  limited: "bg-gray-50  border border-gray-200  text-gray-600",
  good: "bg-blue-50  border border-blue-200  text-blue-800",
  excellent: "bg-green-50 border border-green-200 text-green-800",
};
const BANNER_TEXT: Record<string, (n: string) => string> = {
  insufficient: (n) => `⚠️ 資料累積不足 30 天（現有 ${n} 天），IVR/IVP 尚不可靠`,
  limited: (n) => `📊 資料累積中（${n} 天），建議等待更多歷史資料`,
  good: (n) => `✅ 資料品質良好（${n} 天）`,
  excellent: (n) => `✅ 資料充足（${n} 天），統計結果可信`,
};

const QUALITY_BADGE: Record<string, string> = {
  insufficient: "bg-yellow-100 text-yellow-700",
  limited: "bg-gray-100 text-gray-600",
  good: "bg-blue-100 text-blue-700",
  excellent: "bg-green-100 text-green-700",
};
const QUALITY_LABEL: Record<string, string> = {
  insufficient: "累積中",
  limited: "有限",
  good: "良好",
  excellent: "充足",
};

// ── Skew tooltip 文案 ───────────────────────────────────────────────────
const SKEW_TIPS: Record<string, string> = {
  put: "Put IV (25δ)\n\n價外 Put 的隱含波動率。\n數值越高代表市場願意付更多錢買下跌保護，\n反映偏空情緒或避險需求強烈。",
  call: "Call IV (25δ)\n\n價外 Call 的隱含波動率。\n數值越高代表市場願意付更多溢價買上漲曝險，\n反映偏多情緒或投機需求旺盛。",
  skew: "Skew (pts)\n\nPut IV 減去 Call IV 的差值（單位：百分點）。\n正值(+) → Put 比 Call 貴，市場偏空/避險。\n負值(-) → Call 比 Put 貴，市場偏多/投機。",
  rank: "Skew Rank\n\n當前 Skew 在過去歷史中的相對位置。\n100 = 最偏空（Put 溢價最高）\n0 = 最偏多（Call 溢價最高）\n需累積≥5天資料才顯示指針。",
};

function degToXY(cx: number, cy: number, r: number, deg: number): [number, number] {
  const rad = deg * Math.PI / 180;
  return [cx + r * Math.cos(rad), cy + r * Math.sin(rad)];
}

function buildArcPath(cx: number, cy: number, r: number, startDeg: number, endDeg: number): string {
  const s = degToXY(cx, cy, r, startDeg);
  const e = degToXY(cx, cy, r, endDeg);
  const large = (endDeg - startDeg) > 180 ? 1 : 0;
  return `M${s[0].toFixed(1)},${s[1].toFixed(1)}`
    + ` A${r},${r} 0 ${large} 1 `
    + `${e[0].toFixed(1)},${e[1].toFixed(1)}`;
}

// 結合 ivr 與 skew_rank 的策略標籤
function strategyInfo(ivr: number | null, skewRank: number | null): { text: string; color: string } {
  const ivHigh = ivr !== null && ivr >= 60;
  const ivLow = ivr !== null && ivr < 30;
  const skHigh = skewRank !== null && skewRank >= 60;
  const skLow = skewRank !== null && skewRank < 30;
  if (ivr === null) return { text: "觀望", color: "#9ca3af" };
  if (ivHigh && skHigh) return { text: "適合賣 Call・偏空", color: "#dc2626" };
  if (ivHigh && skLow) return { text: "適合 CSP・偏多", color: "#ea580c" };
  if (ivHigh) return { text: "適合賣方・方向中性", color: "#ea580c" };
  if (ivLow && skLow) return { text: "適合買 Call", color: "#16a34a" };
  if (ivLow && skHigh) return { text: "適合買 Put", color: "#dc2626" };
  return { text: "觀望", color: "#9ca3af" };
}

function ttsIcons(text: string): string {
  const spk = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" width="11" height="11" class="ivdash-spk-icon"><path d="M9.383 3.076A1 1 0 0110 4v12a1 1 0 01-1.707.707L4.586 13H2a1 1 0 01-1-1V8a1 1 0 011-1h2.586l3.707-3.707a1 1 0 011.09-.217zM12.293 7.293a1 1 0 011.414 1.414 3 3 0 010 4.243 1 1 0 01-1.414-1.414 1 1 0 000-1.415 1 1 0 010-1.414z"/></svg>';
  // 樣式改走 class：innerHTML 裡的 style 屬性同樣受 CSP style-src 管轄。
  return `<button class="card-tts-btn ivdash-tts ivdash-tts-male" data-tts-text="${text}" data-tts-gender="male" title="男聲朗讀">${spk}</button>`
    + `<button class="card-tts-btn ivdash-tts ivdash-tts-female" data-tts-text="${text}" data-tts-gender="female" title="女聲朗讀">${spk}</button>`;
}

function pct1(v: number | undefined): string | null {
  return v === undefined ? null : `${(v * 100).toFixed(1)}%`;
}

function buildGaugeCard(item: WatchlistItem, mode: string): string {
  const W = 128, H = 86, cx = 64, cy = 68, r = 50, sw = 10;
  const isIvr = mode !== "skew";

  const rankRaw = isIvr ? item.ivr_1y : item.skew_rank;
  const rank: number | null = rankRaw === undefined ? null : rankRaw;

  // IV Rank：暖色系（橘/紅框）；Skew Rank：冷色系（藍/青框）
  let needleColor: string, borderColor: string, segLow: string, segMid: string, segHigh: string;
  if (isIvr) {
    segLow = "#2ecc8e"; segMid = "#e6952a"; segHigh = "#e05252";
    needleColor = rank === null ? "#9ca3af"
      : rank >= 60 ? "#e05252" : rank >= 30 ? "#e6952a" : "#2ecc8e";
    borderColor = rank === null ? "#e5e7eb"
      : rank >= 60 ? "#fecaca" : rank >= 30 ? "#fed7aa" : "#bbf7d0";
  } else {
    // Skew：>= 60 紅、30-60 灰、< 30 綠
    segLow = "#22d3ee"; segMid = "#94a3b8"; segHigh = "#f87171";
    needleColor = rank === null ? "#9ca3af"
      : rank >= 60 ? "#f87171" : rank >= 30 ? "#94a3b8" : "#22d3ee";
    borderColor = rank === null ? "#e5e7eb"
      : rank >= 60 ? "#fecaca" : rank >= 30 ? "#e2e8f0" : "#a5f3fc";
  }

  let svg = "";
  svg += `<path d="${buildArcPath(cx, cy, r, 180, 360)}" fill="none" stroke="#f3f4f6" stroke-width="${sw}" stroke-linecap="butt"/>`;

  if (rank !== null) {
    svg += `<path d="${buildArcPath(cx, cy, r, 180, 234)}" fill="none" stroke="${segLow}" stroke-width="${sw}" stroke-linecap="butt"/>`;
    svg += `<path d="${buildArcPath(cx, cy, r, 234, 288)}" fill="none" stroke="${segMid}" stroke-width="${sw}" stroke-linecap="butt"/>`;
    svg += `<path d="${buildArcPath(cx, cy, r, 288, 360)}" fill="none" stroke="${segHigh}" stroke-width="${sw}" stroke-linecap="butt"/>`;

    const ndeg = (180 + rank / 100 * 180) * Math.PI / 180;
    const nl = r * 0.76;
    svg += `<line x1="${cx}" y1="${cy}"`
      + ` x2="${(cx + nl * Math.cos(ndeg)).toFixed(1)}"`
      + ` y2="${(cy + nl * Math.sin(ndeg)).toFixed(1)}"`
      + ` stroke="${needleColor}" stroke-width="2.5" stroke-linecap="round"/>`;
    svg += `<circle cx="${cx}" cy="${cy}" r="3.5" fill="${needleColor}"/>`;
  }

  svg += `<text x="${cx}" y="${cy + 16}"`
    + ` text-anchor="middle" font-size="15" font-weight="700" fill="${needleColor}">`
    + `${rank !== null ? rank.toFixed(1) : "—"}</text>`;
  const rankTipHtml = !isIvr
    ? '<div class="ivdash-rank-tip">'
      + '<span data-tip-key="rank" class="ivdash-tip-q">❓ Skew Rank</span>'
      + `${ttsIcons("Skew Rank")}</div>`
    : "";

  const lp = degToXY(cx, cy, r, 180);
  const rp = degToXY(cx, cy, r, 360);
  svg += `<text x="${(lp[0] + 6).toFixed(0)}" y="${(lp[1] + 4).toFixed(0)}" text-anchor="middle" font-size="7" fill="#9ca3af">0</text>`;
  svg += `<text x="${(rp[0] - 6).toFixed(0)}" y="${(rp[1] + 4).toFixed(0)}" text-anchor="middle" font-size="7" fill="#9ca3af">100</text>`;

  // 底部細節（10px 灰字）
  let detailLine: string;
  if (isIvr) {
    const atmPct = pct1(item.latest_atm_iv);
    const atmStr = atmPct !== null ? `ATM IV: ${atmPct}` : (rank === null ? "尚無資料" : "");
    detailLine = `<div class="ivdash-detail">${atmStr}${ttsIcons("ATM IV")}</div>`;
  } else {
    const putStr = pct1(item.put_iv_025) ?? "—";
    const callStr = pct1(item.call_iv_025) ?? "—";
    const skewStr = item.skew_pts !== undefined
      ? `${item.skew_pts >= 0 ? "+" : ""}${item.skew_pts.toFixed(1)} pts` : "—";
    detailLine =
      '<div class="ivdash-detail">'
        + `Put: ${putStr}`
        + `<span data-tip-key="put" class="ivdash-tip-q-inline">❓</span>${ttsIcons("Put")}`
        + ` | Call: ${callStr}`
        + `<span data-tip-key="call" class="ivdash-tip-q-inline">❓</span>${ttsIcons("Call")}`
      + "</div>"
      + '<div class="ivdash-detail-flat">'
        + `Skew: ${skewStr}`
        + `<span data-tip-key="skew" class="ivdash-tip-q-inline">❓</span>${ttsIcons("Skew")}`
      + "</div>";
  }

  // 策略標籤
  const strat = strategyInfo(item.ivr_1y ?? null, item.skew_rank ?? null);
  // 策略色與邊框色由資料決定，走 data-accent-*，插入 DOM 後由 applyDataStyles()
  // 以 CSSOM 套用（CSP 擋的是 HTML 的 style 屬性，不是 CSSOM 賦值）。
  const stratDiv = `<div class="ivdash-strat" data-accent-color="${strat.color}">${strat.text}</div>`;

  return `<div class="iv-dash-card ivdash-card" data-ticker="${item.ticker}" data-accent-border="${borderColor}">`
    + `<div class="ivdash-ticker">${item.ticker}</div>`
    + `<svg width="${W}" height="${H}" viewBox="0 0 ${W} ${H}">${svg}</svg>`
    + rankTipHtml
    + detailLine
    + stratDiv
    + "</div>";
}

export function init(): void {
  // ── Call/Put 切換 ─────────────────────────────────────────────
  const callBtn = document.getElementById("iv-type-call");
  const putBtn = document.getElementById("iv-type-put");
  const typeInput = document.getElementById("iv-option-type");
  if (callBtn && putBtn && typeInput instanceof HTMLInputElement) {
    callBtn.addEventListener("click", () => {
      callBtn.className = ACTIVE;
      putBtn.className = INACTIVE;
      typeInput.value = "call";
    });
    putBtn.addEventListener("click", () => {
      putBtn.className = ACTIVE;
      callBtn.className = INACTIVE;
      typeInput.value = "put";
    });
  }

  // ── 到期日下拉動態載入 ────────────────────────────────────────
  const tickerEl = document.getElementById("iv-ticker");
  const tickerInput = tickerEl instanceof HTMLInputElement ? tickerEl : null;
  const expiryEl = document.getElementById("iv-expiry");
  const expirySelect = expiryEl instanceof HTMLSelectElement ? expiryEl : null;

  function buildExpiryOptions(expirations: string[], weeklyCount: number): void {
    if (!expirySelect) return;
    expirySelect.innerHTML = "";
    const near = expirations.slice(0, weeklyCount);
    const far = expirations.slice(weeklyCount);

    function addGroup(label: string, dates: string[]): void {
      if (!dates.length || !expirySelect) return;
      const grp = document.createElement("optgroup");
      grp.label = label;
      dates.forEach((d, i) => {
        const opt = document.createElement("option");
        opt.value = d;
        opt.textContent = d.replace(/-/g, "/");
        if (i === 0 && label.indexOf("近期") >= 0) opt.selected = true;
        grp.appendChild(opt);
      });
      expirySelect.appendChild(grp);
    }

    addGroup("近期（週選）", near);
    addGroup("月選 / LEAPS", far);
  }

  function loadExpirations(ticker: string): void {
    if (!ticker) return;
    fetch(`/api/iv_analysis/expirations?ticker=${encodeURIComponent(ticker)}`)
      .then((r) => r.json())
      .then((data: unknown) => {
        const expirations = arr(data, "expirations")
          .filter((v): v is string => typeof v === "string");
        if (expirations.length) {
          buildExpiryOptions(expirations, numeric(data, "weekly_count") ?? 6);
        }
      })
      .catch(() => {});
  }

  tickerInput?.addEventListener("blur", () => {
    const t = tickerInput.value.toUpperCase().trim();
    if (t.length >= 1) loadExpirations(t);
  });

  // ── 表單送出 ──────────────────────────────────────────────────
  const form = document.getElementById("iv-analysis-form");
  const submitEl = document.getElementById("iv-submit-btn");
  const errorMsg = document.getElementById("iv-error-msg");

  if (form instanceof HTMLFormElement && submitEl instanceof HTMLButtonElement && errorMsg) {
    const submitBtn: HTMLButtonElement = submitEl;
    const errEl: HTMLElement = errorMsg;
    form.addEventListener("submit", (e) => {
      e.preventDefault();
      const fd = new FormData(form);
      const payload = {
        ticker: String(fd.get("ticker") ?? "").toUpperCase().trim(),
        strike: parseFloat(String(fd.get("strike") ?? "")),
        expiry_date: fd.get("expiry_date"),
        option_type: fd.get("option_type"),
      };

      errEl.classList.add("hidden");
      errEl.textContent = "";
      submitBtn.disabled = true;
      submitBtn.textContent = "查詢中…";

      fetch("/api/iv_analysis", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": csrfToken(),
        },
        body: JSON.stringify(payload),
      })
        .then((res) => res.json().then((data: unknown) => ({ ok: res.ok, data })))
        .then((r) => {
          if (!r.ok) throw new Error(str(r.data, "error") ?? "查詢失敗");
          renderResult(r.data);
          loadWatchlist();
        })
        .catch((err: unknown) => {
          errEl.textContent = err instanceof Error ? err.message : String(err);
          errEl.classList.remove("hidden");
        })
        .finally(() => {
          submitBtn.disabled = false;
          submitBtn.textContent = "查詢 IV";
        });
    });
  }

  // ── 渲染查詢結果 ──────────────────────────────────────────────
  function setText(id: string, text: string): void {
    const el = document.getElementById(id);
    if (el) el.textContent = text;
  }

  function renderResult(d: unknown): void {
    document.getElementById("iv-result-section")?.classList.remove("hidden");
    setText("iv-result-ticker",
      `${str(d, "ticker") ?? ""} ${(str(d, "option_type") ?? "").toUpperCase()} `
      + `${numeric(d, "strike") ?? ""} ${str(d, "expiry_date") ?? ""}`);

    const snapWarn = document.getElementById("iv-snap-warning");
    const snapNotice = str(d, "snap_notice");
    if (snapWarn) {
      if (snapNotice) {
        snapWarn.textContent = snapNotice;
        snapWarn.classList.remove("hidden");
      } else {
        snapWarn.classList.add("hidden");
        snapWarn.textContent = "";
      }
    }
    setText("iv-result-time", new Date(str(d, "queried_at") ?? "").toLocaleString("zh-TW"));
    setText("iv-card-price", `$${(numeric(d, "current_price") ?? NaN).toFixed(2)}`);

    const deltaEl = document.getElementById("iv-card-delta");
    const delta = numeric(d, "delta") ?? NaN;
    if (deltaEl) {
      deltaEl.textContent = delta.toFixed(4);
      deltaEl.className = "text-lg font-bold "
        + (delta > 0.5 ? "text-blue-600" : delta >= 0.3 ? "text-green-600" : "text-gray-500");
    }

    setText("iv-card-iv", `${((numeric(d, "iv") ?? NaN) * 100).toFixed(2)}%`);

    const dte = numeric(d, "dte");
    setText("iv-card-dte", dte !== undefined ? `${dte} 天` : "—");

    const atmIv = numeric(d, "atm_iv");
    setText("iv-card-atm", atmIv !== undefined ? `${(atmIv * 100).toFixed(2)}%` : "—%");

    const hvEl = document.getElementById("iv-card-hv");
    const hvWin = document.getElementById("iv-card-hv-window");
    const hvDte = numeric(d, "hv_dte");
    if (hvEl) {
      if (hvDte !== undefined) {
        const hvPct = hvDte * 100;
        const atm = atmIv !== undefined ? atmIv * 100 : null;
        hvEl.textContent = `${hvPct.toFixed(2)}%`;
        hvEl.className = "text-lg font-bold "
          + (atm !== null && hvPct > atm + 5 ? "text-green-600"
            : atm !== null && hvPct < atm - 5 ? "text-orange-500" : "text-gray-800");
        const hvWindow = str(d, "hv_window");
        if (hvWin && hvWindow) hvWin.textContent = hvWindow;
      } else {
        hvEl.textContent = "—%";
        hvEl.className = "text-lg font-bold text-gray-800";
        if (hvWin) hvWin.textContent = "—";
      }
    }

    renderIvrCell("iv-ivr-1y", numeric(d, "ivr_1y"));
    renderIvrCell("iv-ivr-2y", numeric(d, "ivr_2y"));
    renderStatCell("iv-ivp-1y", numeric(d, "ivp_1y"));
    renderStatCell("iv-ivp-2y", numeric(d, "ivp_2y"));

    renderQualityBanner(str(d, "data_quality") ?? "", numeric(d, "available_days"), str(d, "notice"));
    renderConclusion(numeric(d, "ivr_1y"), numeric(d, "ivr_2y"));
  }

  function renderIvrCell(id: string, val: number | undefined): void {
    const el = document.getElementById(id);
    if (!el) return;
    if (val === undefined) {
      el.textContent = "—";
      el.className = "py-2 text-center text-gray-400";
      return;
    }
    el.textContent = `${val.toFixed(1)}%`;
    if (val < 20) el.className = "py-2 text-center font-semibold text-green-600";
    else if (val > 80) el.className = "py-2 text-center font-semibold text-red-600";
    else el.className = "py-2 text-center font-medium text-gray-700";
  }

  function renderStatCell(id: string, val: number | undefined): void {
    const el = document.getElementById(id);
    if (!el) return;
    if (val === undefined) {
      el.textContent = "—";
      el.className = "py-2 text-center text-gray-400";
    } else {
      el.textContent = `${val.toFixed(1)}%`;
      el.className = "py-2 text-center font-medium text-gray-700";
    }
  }

  function renderQualityBanner(quality: string, days: number | undefined, notice: string | undefined): void {
    const el = document.getElementById("iv-quality-banner");
    if (!el) return;
    const n = String(days ?? "");
    const builder = BANNER_TEXT[quality];
    let txt = builder ? builder(n) : `${n} 天`;
    // 全形空格是原碼刻意的分隔符；放在 template literal 裡會被 ESLint 的
    // no-irregular-whitespace 抓（該規則預設 skipStrings 但不 skipTemplates），
    // 所以維持字串串接，字元本身原封不動。
    if (notice && quality !== "insufficient") txt += "\u3000" + notice;
    el.textContent = txt;
    el.className = `mb-4 px-4 py-2.5 rounded-lg text-sm ${BANNER_STYLES[quality] ?? ""}`;
    el.classList.remove("hidden");
  }

  function renderConclusion(ivr1yRaw: number | undefined, ivr2yRaw: number | undefined): void {
    const el = document.getElementById("iv-conclusion");
    if (!el) return;
    const ivr_1y = ivr1yRaw ?? null;
    const ivr_2y = ivr2yRaw ?? null;
    let text: string, cls: string;

    if (ivr_1y === null) {
      text = "IV 歷史資料不足，暫無信號";
      cls = "mt-4 px-4 py-3 rounded-lg text-sm bg-gray-50 text-gray-500";
    } else if (ivr_1y < 20 && ivr_2y !== null && ivr_2y < 20) {
      text = "✅ IV 同時處於一年及兩年低點，買入期權信號較強";
      cls = "mt-4 px-4 py-3 rounded-lg text-sm bg-green-50 text-green-800 font-medium";
    } else if (ivr_1y < 20) {
      text = "✅ IV 處於一年低點，買入期權勝算較高";
      cls = "mt-4 px-4 py-3 rounded-lg text-sm bg-green-50 text-green-700";
    } else if (ivr_1y > 80) {
      text = "⚠️ IV 偏高，Vega 風險大，考慮賣方策略";
      cls = "mt-4 px-4 py-3 rounded-lg text-sm bg-red-50 text-red-700";
    } else {
      text = `IV 處於中性區間（IVR ${ivr_1y.toFixed(1)}%）`;
      cls = "mt-4 px-4 py-3 rounded-lg text-sm bg-gray-50 text-gray-600";
    }
    el.textContent = text;
    el.className = cls;
    el.classList.remove("hidden");
  }

  // ── Tooltip ───────────────────────────────────────────────────
  function initTooltip(): void {
    const tip = document.createElement("div");
    tip.id = "iv-global-tip";
    tip.style.cssText = [
      "position:fixed", "z-index:9999", "display:none",
      "max-width:240px", "background:#1e293b", "color:#e2e8f0",
      "font-size:12px", "line-height:1.55", "white-space:pre-line",
      "padding:8px 10px", "border-radius:8px",
      "box-shadow:0 4px 16px rgba(0,0,0,.35)",
      "pointer-events:none", "transition:opacity .15s",
    ].join(";");
    document.body.appendChild(tip);

    let lastTipEl: HTMLElement | null = null;

    function showTip(el: HTMLElement, e: MouseEvent): void {
      const key = el.dataset["tipKey"];
      const body = key === undefined ? undefined : SKEW_TIPS[key];
      if (!body) return;
      tip.textContent = body;
      tip.style.display = "block";
      moveTip(e);
    }
    function moveTip(e: MouseEvent): void {
      let px = e.clientX + 14;
      let py = e.clientY - 10;
      if (px + 250 > window.innerWidth) px = e.clientX - 254;
      if (py + tip.offsetHeight > window.innerHeight) py = e.clientY - tip.offsetHeight - 6;
      tip.style.left = `${px}px`;
      tip.style.top = `${py}px`;
    }
    function hideTip(): void {
      tip.style.display = "none";
      lastTipEl = null;
    }

    document.addEventListener("mouseover", (e) => {
      const el = closestFrom(e, "[data-tip-key]");
      if (!el) return;
      lastTipEl = el;
      showTip(el, e);
    });
    document.addEventListener("mousemove", (e) => {
      if (tip.style.display === "none") return;
      moveTip(e);
    });
    document.addEventListener("mouseout", (e) => {
      if (closestFrom(e, "[data-tip-key]")) hideTip();
    });
    document.addEventListener("click", (e) => {
      const el = closestFrom(e, "[data-tip-key]");
      if (!el) { hideTip(); return; }
      if (lastTipEl === el && tip.style.display !== "none") { hideTip(); return; }
      lastTipEl = el;
      showTip(el, e);
    });
  }

  // ── 儀表板 ────────────────────────────────────────────────────
  let _dashMode = "ivr"; // 'ivr' | 'skew'
  let _watchlistData: WatchlistItem[] = [];

  window.switchDashMode = (mode: string): void => {
    _dashMode = mode;
    const ivrBtn = document.getElementById("dash-mode-ivr");
    const skewBtn = document.getElementById("dash-mode-skew");
    if (ivrBtn && skewBtn) {
      if (mode === "ivr") {
        ivrBtn.className = "px-3 py-1.5 bg-orange-500 text-white transition-colors";
        skewBtn.className = "px-3 py-1.5 bg-white text-gray-600 hover:bg-gray-50 transition-colors";
      } else {
        ivrBtn.className = "px-3 py-1.5 bg-white text-gray-600 hover:bg-gray-50 transition-colors";
        skewBtn.className = "px-3 py-1.5 bg-cyan-500 text-white transition-colors";
      }
    }
    renderDashboard(_watchlistData, mode);
  };

  function rankOf(item: WatchlistItem, isIvr: boolean): number | undefined {
    return isIvr ? item.ivr_1y : item.skew_rank;
  }

  function renderDashboard(list: WatchlistItem[], mode: string): void {
    const summaryEl = document.getElementById("iv-dashboard-summary");
    const cardsEl = document.getElementById("iv-dashboard-cards");
    const isIvr = mode !== "skew";
    if (!summaryEl || !cardsEl) return;

    const setCls = (id: string, cls: string): void => {
      const el = document.getElementById(id);
      if (el) el.className = cls;
    };

    // 更新摘要列標籤
    if (isIvr) {
      setText("dash-sum-high-label", "High Vol · IVR ≥ 60");
      setText("dash-sum-mid-label", "Neutral · 30–60");
      setText("dash-sum-low-label", "Low Vol · IVR < 30");
      setCls("dash-sum-high-box", "rounded-lg p-3 text-center bg-red-50");
      setCls("dash-sum-mid-box", "rounded-lg p-3 text-center bg-gray-50");
      setCls("dash-sum-low-box", "rounded-lg p-3 text-center bg-green-50");
      setCls("dash-sum-high-label", "text-xs font-medium text-red-700");
      setCls("dash-sum-mid-label", "text-xs font-medium text-gray-600");
      setCls("dash-sum-low-label", "text-xs font-medium text-green-700");
      setCls("iv-summary-high-count", "text-2xl font-bold text-red-600 mt-1");
      setCls("iv-summary-mid-count", "text-2xl font-bold text-gray-500 mt-1");
      setCls("iv-summary-low-count", "text-2xl font-bold text-green-600 mt-1");
    } else {
      setText("dash-sum-high-label", "High Put Skew ≥ 60");
      setText("dash-sum-mid-label", "Balanced Skew 30–60");
      setText("dash-sum-low-label", "Low Put Skew < 30");
      setCls("dash-sum-high-box", "rounded-lg p-3 text-center bg-red-50");
      setCls("dash-sum-mid-box", "rounded-lg p-3 text-center bg-slate-50");
      setCls("dash-sum-low-box", "rounded-lg p-3 text-center bg-cyan-50");
      setCls("dash-sum-high-label", "text-xs font-medium text-red-700");
      setCls("dash-sum-mid-label", "text-xs font-medium text-slate-500");
      setCls("dash-sum-low-label", "text-xs font-medium text-cyan-700");
      setCls("iv-summary-high-count", "text-2xl font-bold text-red-600 mt-1");
      setCls("iv-summary-mid-count", "text-2xl font-bold text-slate-500 mt-1");
      setCls("iv-summary-low-count", "text-2xl font-bold text-cyan-600 mt-1");
    }

    if (!list.length) {
      cardsEl.innerHTML = '<span class="ivdash-empty">查詢後自動加入 Watchlist</span>';
      summaryEl.classList.add("hidden");
      return;
    }

    // 摘要計數
    const ranks = list.map((d) => rankOf(d, isIvr)).filter((v): v is number => v !== undefined);
    const high = ranks.filter((v) => v >= 60).length;
    const mid = ranks.filter((v) => v >= 30 && v < 60).length;
    const low = ranks.filter((v) => v < 30).length;

    setText("iv-summary-high-count", String(high));
    setText("iv-summary-mid-count", String(mid));
    setText("iv-summary-low-count", String(low));
    summaryEl.classList.remove("hidden");

    const sorted = list.slice().sort((a, b) =>
      (rankOf(b, isIvr) ?? -1) - (rankOf(a, isIvr) ?? -1));

    cardsEl.innerHTML = sorted.map((item) => buildGaugeCard(item, mode)).join("");
    // 卡片是 innerHTML 產生的，data-accent-* 要在插入後才套得上。
    applyDataStyles(cardsEl);

    cardsEl.querySelectorAll<HTMLElement>(".iv-dash-card").forEach((card) => {
      card.addEventListener("click", () => {
        const ticker = card.dataset["ticker"];
        if (!ticker) return;
        const input = document.getElementById("iv-ticker");
        if (input instanceof HTMLInputElement) input.value = ticker;
        loadExpirations(ticker);
        document.getElementById("iv-analysis-form")
          ?.scrollIntoView({ behavior: "smooth", block: "start" });
      });
      card.addEventListener("mouseover", () => {
        card.style.boxShadow = "0 4px 12px rgba(0,0,0,.12)";
        card.style.transform = "translateY(-2px)";
      });
      card.addEventListener("mouseout", () => {
        card.style.boxShadow = "";
        card.style.transform = "";
      });
    });
    cardsEl.querySelectorAll<HTMLElement>(".card-tts-btn").forEach((btn) => {
      btn.addEventListener("click", (e) => {
        e.stopPropagation();
        const text = btn.dataset["ttsText"];
        const gender = btn.dataset["ttsGender"];
        if (text !== undefined && gender !== undefined) window.ttsSpeak?.(text, gender);
      });
    });
  }

  document.getElementById("dash-mode-ivr")
    ?.addEventListener("click", () => { window.switchDashMode?.("ivr"); });
  document.getElementById("dash-mode-skew")
    ?.addEventListener("click", () => { window.switchDashMode?.("skew"); });

  function loadWatchlist(): void {
    fetch("/api/iv_analysis/watchlist")
      .then((r) => r.json())
      .then((data: unknown) => {
        _watchlistData = arr(data, "watchlist")
          .map(parseItem)
          .filter((v): v is WatchlistItem => v !== null);
        renderWatchlist(_watchlistData);
        renderDashboard(_watchlistData, _dashMode);
      })
      .catch(() => {});
  }

  function recalcRow(ticker: string): void {
    const row = document.getElementById(`wl-row-${ticker}`);
    if (!row) return;
    const S = parseFloat(row.dataset["price"] || "0");
    const sigma = parseFloat(row.dataset["iv"] || "0");
    const type = row.dataset["otype"] || "call";
    const strikeInput = row.querySelector(".wl-strike-input");
    const expiryInput = row.querySelector(".wl-expiry-input");
    const K = parseFloat(
      (strikeInput instanceof HTMLInputElement ? strikeInput.value : "") || "0",
    );
    const expiry = expiryInput instanceof HTMLInputElement ? expiryInput.value : "";
    const days = expiry ? Math.max(0, (new Date(expiry).getTime() - Date.now()) / 86400000) : 0;
    const T = days / 365;
    const intrinsic = type === "call" ? Math.max(0, S - K) : Math.max(0, K - S);
    const timeVal = T > 0 ? 0.4 * S * sigma * Math.sqrt(T) : 0;
    const iEl = row.querySelector(".wl-intrinsic-val");
    const tEl = row.querySelector(".wl-time-val");
    if (iEl) {
      iEl.textContent = `$${intrinsic.toFixed(2)}`;
      iEl.className = `wl-intrinsic-val font-mono text-sm ${intrinsic > 0 ? "text-blue-600" : "text-gray-400"}`;
    }
    if (tEl) tEl.textContent = `$${timeVal.toFixed(2)}`;
  }

  function ivrCell(val: number | undefined): string {
    if (val === undefined) return '<td class="px-4 py-3 text-right text-gray-300">—</td>';
    const cls = val < 20 ? "font-semibold text-green-600" : val > 80 ? "font-semibold text-red-600" : "text-gray-700";
    return `<td class="px-4 py-3 text-right"><span class="font-mono text-sm ${cls}">${val.toFixed(1)}%</span></td>`;
  }
  function ivpCell(val: number | undefined): string {
    if (val === undefined) return '<td class="px-4 py-3 text-right text-gray-300">—</td>';
    return `<td class="px-4 py-3 text-right"><span class="font-mono text-sm text-gray-600">${val.toFixed(1)}%</span></td>`;
  }

  function renderWatchlist(list: WatchlistItem[]): void {
    const tbody = document.getElementById("iv-watchlist-body");
    if (!tbody) return;
    if (!list.length) {
      tbody.innerHTML = '<tr><td colspan="14" class="px-4 py-8 text-center text-sm text-gray-400">尚無追蹤中的股票</td></tr>';
      return;
    }
    tbody.innerHTML = list.map((item) => {
      const iv = item.latest_atm_iv !== undefined
        ? `${(item.latest_atm_iv * 100).toFixed(2)}%` : "—";
      const quality = item.data_quality ?? "";
      const badge = QUALITY_BADGE[quality] ?? "bg-gray-100 text-gray-500";
      const label = QUALITY_LABEL[quality] ?? quality;
      const ts = item.last_fetched_at
        ? new Date(item.last_fetched_at).toLocaleDateString("zh-TW") : "—";

      let intrinsicCell: string, timeCell: string;
      if (item.intrinsic_value !== undefined) {
        const liveTag = item.is_live
          ? '<span title="即時報價" class="ivdash-live-dot">🟢</span>'
          : '<span title="使用快取值，點重新整理取得即時數據" class="ivdash-live-dot">⚪</span>';
        const sub = item.query_label
          ? `<br><span class="ivdash-sub">${item.query_label}${liveTag}</span>`
          : "";
        intrinsicCell = '<td class="px-4 py-3 text-right">'
          + `<span class="wl-intrinsic-val font-mono text-sm ${item.intrinsic_value > 0 ? "text-blue-600" : "text-gray-400"}">`
          + `$${item.intrinsic_value.toFixed(2)}</span>${sub}</td>`;
        timeCell = '<td class="px-4 py-3 text-right">'
          + '<span class="wl-time-val font-mono text-sm text-orange-500">$'
          + `${(item.time_value ?? NaN).toFixed(2)}</span>${sub}</td>`;
      } else {
        intrinsicCell = '<td class="px-4 py-3 text-right text-gray-300 text-xs">尚無查詢</td>';
        timeCell = '<td class="px-4 py-3 text-right text-gray-300 text-xs">—</td>';
      }

      const typeTag = item.option_type
        ? `<span class="inline-block px-1.5 py-0.5 rounded text-xs font-bold mr-1.5 ${item.option_type === "call" ? "bg-green-100 text-green-700" : "bg-red-100 text-red-700"}">${item.option_type.toUpperCase()}</span>`
        : "";
      const strikeCell = item.strike !== undefined
        ? `<td class="px-3 py-2 text-right">${typeTag}<input type="number" class="wl-strike-input font-mono text-sm text-gray-700 w-20 text-right border border-gray-200 rounded px-1.5 py-0.5 hover:border-blue-400 focus:border-blue-500 focus:outline-none" value="${item.strike.toFixed(1)}" step="0.5" data-ticker="${item.ticker}"></td>`
        : '<td class="px-3 py-2 text-right text-gray-300">—</td>';
      const expiryCell = item.expiry_date !== undefined
        ? `<td class="px-3 py-2 text-right"><input type="date" class="wl-expiry-input text-sm text-gray-700 border border-gray-200 rounded px-1.5 py-0.5 hover:border-blue-400 focus:border-blue-500 focus:outline-none" value="${item.expiry_date}" data-ticker="${item.ticker}"></td>`
        : '<td class="px-3 py-2 text-right text-gray-300">—</td>';

      return `<tr class="border-b border-gray-50 hover:bg-gray-50 transition-colors" id="wl-row-${item.ticker}" data-price="${item.live_price ?? ""}" data-iv="${item.live_iv ?? ""}" data-otype="${item.option_type ?? "call"}">`
        + `<td class="px-4 py-3 font-semibold text-gray-800">${item.ticker}</td>`
        + `<td class="px-4 py-3 text-right font-mono text-gray-700">${iv}</td>`
        + ivrCell(item.ivr_1y)
        + ivpCell(item.ivp_1y)
        + ivrCell(item.ivr_2y)
        + ivpCell(item.ivp_2y)
        + strikeCell
        + expiryCell
        + intrinsicCell
        + timeCell
        + `<td class="px-4 py-3 text-right text-gray-600">${item.available_days ?? ""} 天</td>`
        + `<td class="px-4 py-3 text-center"><span class="inline-block px-2 py-0.5 rounded-full text-xs font-medium ${badge}">${label}</span></td>`
        + `<td class="px-4 py-3 text-right text-gray-400 text-xs">${ts}</td>`
        + '<td class="px-4 py-3 text-center">'
          + `<button class="wl-remove-btn text-xs text-red-400 hover:text-red-600 transition-colors" data-ticker="${item.ticker}">移除</button>`
        + "</td></tr>";
    }).join("");
  }

  document.getElementById("iv-watchlist-refresh")
    ?.addEventListener("click", loadWatchlist);

  document.addEventListener("input", (e) => {
    const el = e.target;
    if (!(el instanceof HTMLElement)) return;
    if (el.classList.contains("wl-strike-input") || el.classList.contains("wl-expiry-input")) {
      const ticker = el.dataset["ticker"];
      if (ticker) recalcRow(ticker);
    }
  });

  document.addEventListener("click", (e) => {
    const btn = closestFrom(e, ".wl-remove-btn");
    if (!btn) return;
    const ticker = btn.dataset["ticker"];
    if (!ticker) return;
    fetch(`/api/iv_analysis/watchlist/${ticker}`, {
      method: "DELETE",
      headers: { "X-CSRF-Token": csrfToken() },
    })
      .then(() => {
        const row = document.getElementById(`wl-row-${ticker}`);
        if (!row) return;
        row.style.transition = "opacity 0.3s";
        row.style.opacity = "0";
        setTimeout(() => { row.remove(); }, 300);
      })
      .catch(() => {});
  });

  initTooltip();
  loadWatchlist();
}
