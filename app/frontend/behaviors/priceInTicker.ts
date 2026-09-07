/**
 * Price-In 反推工具：代號與現價帶入（規格 S2B）。
 *
 * 三條規則，每一條都是為了避免「安靜地輸出一張錯誤的圖」：
 *
 *  1. 頁面載入時不自動抓價，一律由使用者按鈕觸發。這是估值工具不是報價看板，
 *     自動抓價會讓人誤以為圖表隨行情更新。
 *  2. 手動改價 → 時間戳清空，改顯示「手動輸入」，避免把假設價當成真實報價。
 *  3. 代號一改 → 價格立即標記為失效並顯示警示。頁首寫著 AVGO、價格還是 MRVL 的
 *     223.55，這種圖不會報錯也不會測試失敗，就是安靜地錯。
 */

import { isRecord } from "./shared/json";

/** 與 PriceIn::ScenarioForm::MAX_MULTIPLES 對齊。 */
const MAX_MULTIPLES = 5;

interface PeRange { low: number | null; high: number | null; current: number | null }

interface Estimate {
  low: number | null;
  high: number | null;
  avg: number | null;
  analysts: number | null;
  end_date: string | null;
}

interface QuoteOk {
  ok: true;
  ticker: string;
  price: number;
  as_of: string;
  eps_ttm: number | null;
  pe: PeRange;
  forward_pe: PeRange;
  peer_low: number | null;
  peer_high: number | null;
  eps_estimate: Estimate;
  eps_estimate_next: Estimate;
}
interface QuoteErr { ok: false; error_code: string; message: string }

function parseQuote(raw: unknown): QuoteOk | QuoteErr | null {
  if (!isRecord(raw)) return null;
  if (raw.ok === true) {
    const { ticker, price, as_of: asOf } = raw;
    if (typeof ticker !== "string" || typeof price !== "number" || typeof asOf !== "string") return null;
    // 估值欄位缺值是正常情況（虧損公司、上游沒給、同業樣本不足），不是解析失敗。
    return {
      ok: true, ticker, price, as_of: asOf,
      eps_ttm: num(raw.eps_ttm),
      pe: range(raw.pe),
      forward_pe: range(raw.forward_pe),
      peer_low: num(raw.peer_low),
      peer_high: num(raw.peer_high),
      eps_estimate: estimate(raw.eps_estimate),
      eps_estimate_next: estimate(raw.eps_estimate_next),
    };
  }
  if (raw.ok === false) {
    const { error_code: code, message } = raw;
    if (typeof code !== "string" || typeof message !== "string") return null;
    return { ok: false, error_code: code, message };
  }
  return null;
}

function num(value: unknown): number | null {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

function range(value: unknown): PeRange {
  if (!isRecord(value)) return { low: null, high: null, current: null };
  return { low: num(value.low), high: num(value.high), current: num(value.current) };
}

/**
 * 本益比一律顯示為區間：股價當天一直在動，同一個 EPS 除當日最低與最高價，
 * 得到的倍數可以差好幾倍。只報一個數字等於把那一瞬間的成交價講成公司的估值。
 */
function formatRange(r: PeRange): string {
  if (r.low !== null && r.high !== null) return `${r.low.toFixed(2)} - ${r.high.toFixed(2)}x`;
  if (r.current !== null) return `${r.current.toFixed(2)}x`;
  return "—";
}

function estimate(value: unknown): Estimate {
  if (!isRecord(value)) return { low: null, high: null, avg: null, analysts: null, end_date: null };
  const end = value.end_date;
  return {
    low: num(value.low), high: num(value.high), avg: num(value.avg),
    analysts: num(value.analysts),
    end_date: typeof end === "string" ? end : null,
  };
}

/** 帶入時要塞進倍數欄位的值。小數位與畫面顯示一致，使用者才對得起來。 */
function applyValues(r: PeRange): string[] {
  if (r.low !== null && r.high !== null) return [r.low.toFixed(2), r.high.toFixed(2)];
  if (r.current !== null) return [r.current.toFixed(2)];
  return [];
}

function formatMoney(value: number): string {
  return `$${value.toFixed(2)}`;
}

function formatStamp(iso: string): string {
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return iso;
  const pad = (n: number): string => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

export function init(root: HTMLElement): void {
  const button = root.querySelector("#price-in-fetch-quote");
  const status = root.querySelector("#price-in-quote-status");
  const tickerField = root.querySelector("#price-in-ticker");
  const priceField = root.querySelector("#price-in-price");
  const stampField = root.querySelector("#price-in-price-as-of");
  const entryMirror = root.querySelector("#price-in-entry-a-mirror");
  const multiplesField = root.querySelector("#price-in-chart_a_multiples");

  if (!(button instanceof HTMLButtonElement)) return;
  if (!(tickerField instanceof HTMLInputElement)) return;
  if (!(priceField instanceof HTMLInputElement)) return;

  const quoteUrl = root.dataset.quoteUrl ?? "/price_in/quote";
  let tickerAtLastQuote = tickerField.value.trim().toUpperCase();

  // 以下一律用箭頭常數而非 function 宣告：hoisted 的 function 在 TS 眼中可能
  // 在上面那幾道 instanceof 收窄之前就被呼叫，因此不會套用收窄，
  // 每個 .value 都會變成「Property 'value' does not exist on type 'Element'」。
  const setStatus = (text: string, tone: "muted" | "warn" | "error"): void => {
    if (!(status instanceof HTMLElement)) return;
    status.textContent = text;
    status.className =
      tone === "muted" ? "mt-2 text-[16px] text-gray-500"
      : tone === "warn" ? "mt-2 text-[16px] text-amber-700"
      : "mt-2 text-[16px] text-red-600";
  };

  /** 買入基準恆等於股價，鏡射欄位是唯讀顯示，改價時要跟著動。 */
  const syncMirror = (): void => {
    const value = Number.parseFloat(priceField.value);
    if (entryMirror instanceof HTMLInputElement && Number.isFinite(value)) {
      entryMirror.value = formatMoney(value);
    }
  };

  /** 對照值抓不到就顯示破折號並收起「帶入」按鈕，不顯示錯誤。 */
  const showValue = (valueId: string, applyId: string | null, text: string, source: PeRange): void => {
    const display = document.getElementById(valueId);
    if (display) display.textContent = text;
    if (!applyId) return;

    const apply = document.getElementById(applyId);
    if (!(apply instanceof HTMLElement)) return;

    // 帶入的是畫面上顯示的那組數字：有區間就帶兩端，沒有就帶現價那一個。
    // 顯示區間卻只帶一個值，畫面會自相矛盾。
    const values = applyValues(source);
    apply.hidden = values.length === 0;
    apply.dataset.pe = values.join(",");
  };

  const blank: PeRange = { low: null, high: null, current: null };
  const blankEstimate: Estimate = { low: null, high: null, avg: null, analysts: null, end_date: null };

  /**
   * 分析師 EPS 預測。帶入的是 low／high 兩端而不是平均值——
   * 色帶要畫的是分歧程度，拿平均值會讓色帶縮成一條線。
   */
  const showEstimate = (key: string, est: Estimate, fallbackLabel: string): void => {
    const display = document.getElementById(`price-in-estimate-${key}`);
    const apply = document.getElementById(`price-in-apply-estimate-${key}`);
    const label = document.getElementById(`price-in-estimate-${key}-label`);
    const usable = est.low !== null && est.high !== null;

    if (display) {
      display.textContent = usable
        ? `$${est.low!.toFixed(2)} - $${est.high!.toFixed(2)}`
        : "—";
    }
    // 標題補上年度與分析師家數：光看「本財政年度」對不出是哪一年，
    // 而年度對不上正是最常見的 Price-in 誤判來源。
    if (label) {
      const year = est.end_date ? est.end_date.slice(0, 4) : null;
      const n = est.analysts;
      label.textContent = year
        ? `${fallbackLabel}（截至 ${year}${n ? `，${n} 位分析師` : ""}）`
        : fallbackLabel;
    }
    if (apply instanceof HTMLElement) {
      apply.hidden = !usable;
      if (usable) {
        apply.dataset.low = est.low!.toFixed(2);
        apply.dataset.high = est.high!.toFixed(2);
        apply.dataset.endDate = est.end_date ?? "";
        apply.dataset.analysts = est.analysts !== null ? String(est.analysts) : "";
      }
    }
  };

  const showValuation = (q: QuoteOk | null): void => {
    const pe = q?.pe ?? blank;
    const fwd = q?.forward_pe ?? blank;
    const low = q?.peer_low ?? null;
    const high = q?.peer_high ?? null;

    // 「帶入」帶的是現價對應的那一個倍數，不是區間端點——
    // 帶端點等於替使用者選了當天最貴或最便宜的那一刻。
    showValue("price-in-current-pe", "price-in-apply-pe", formatRange(pe), pe);
    showValue("price-in-forward-pe", "price-in-apply-forward-pe", formatRange(fwd), fwd);
    showValue("price-in-peer-pe", null,
      low === null || high === null ? "—" : `${low.toFixed(2)} - ${high.toFixed(2)}x`, blank);

    const panel = document.getElementById("price-in-estimate-panel");
    const est = q?.eps_estimate ?? blankEstimate;
    const estNext = q?.eps_estimate_next ?? blankEstimate;
    if (panel) panel.hidden = est.low === null && estNext.low === null;
    showEstimate("current", est, "本財政年度");
    showEstimate("next", estNext, "下一財政年度");

    // 記下 TTM EPS，送出後伺服器才判定得出「你填的倍數是不是現價反推的那一個」。
    const hint = document.getElementById("price-in-eps-ttm-hint");
    if (hint instanceof HTMLInputElement) hint.value = q?.eps_ttm != null ? String(q.eps_ttm) : "";

    const epsNote = document.getElementById("price-in-eps-basis");
    if (epsNote) {
      epsNote.textContent = q?.eps_ttm != null
        ? `以 TTM EPS $${q.eps_ttm.toFixed(2)} 換算當日價格區間．上游未標示 GAAP 或非 GAAP`
        : "上游未標示 GAAP 或非 GAAP，僅供對照";
    }
  };

  const markManual = (): void => {
    if (stampField instanceof HTMLInputElement) stampField.value = "";
    setStatus("手動輸入", "muted");
    syncMirror();
  };

  const fetchQuote = async (): Promise<void> => {
    const ticker = tickerField.value.trim().toUpperCase();
    if (ticker === "") { setStatus("請先填入股票代號", "error"); return; }

    button.disabled = true;
    setStatus("查詢中…", "muted");
    try {
      const res = await fetch(`${quoteUrl}?ticker=${encodeURIComponent(ticker)}`, {
        headers: { Accept: "application/json" },
        credentials: "same-origin",
      });
      const parsed = parseQuote(await res.json());

      if (!parsed) { setStatus("報價格式無法解析，請手動輸入", "error"); return; }
      if (!parsed.ok) {
        // 任何失敗都不動價格欄位，圖表照常以現有價格重繪。
        setStatus(parsed.message, "error");
        return;
      }

      priceField.value = String(parsed.price);
      if (stampField instanceof HTMLInputElement) stampField.value = parsed.as_of;
      tickerAtLastQuote = parsed.ticker;
      syncMirror();
      showValuation(parsed);
      setStatus(`報價時間 ${formatStamp(parsed.as_of)}`, "muted");
    } catch {
      setStatus("暫時取不到報價，請手動輸入", "error");
    } finally {
      button.disabled = false;
    }
  };

  button.addEventListener("click", () => { void fetchQuote(); });
  priceField.addEventListener("input", markManual);

  // 「帶入」是使用者明確按下的動作，不是自動填入——規格 §S4 禁止的是
  // 參考倍數自己跑進輸入框，不是禁止使用者主動採用它。
  // 採附加而非覆寫：使用者已經填的假設是他自己的判斷，不該被抹掉。
  const wireApply = (id: string): void => {
    document.getElementById(id)?.addEventListener("click", (event) => {
      if (!(multiplesField instanceof HTMLInputElement)) return;
      const target = event.currentTarget;
      const incoming = (target instanceof HTMLElement ? target.dataset.pe : "")?.split(",") ?? [];
      if (incoming.length === 0) return;

      const current = multiplesField.value.split(",").map((v) => v.trim()).filter((v) => v !== "");
      // Form 層上限 5 個，先擋在這裡免得送出才報錯。裝得下幾個就加幾個，
      // 而不是整批放棄——使用者按了按鈕卻什麼都沒發生，比只加到一半更費解。
      const room = MAX_MULTIPLES - current.length;
      const additions = incoming.filter((v) => v !== "" && !current.includes(v)).slice(0, Math.max(room, 0));
      if (additions.length === 0) return;

      multiplesField.value = [...current, ...additions].join(",");
    });
  };

  wireApply("price-in-apply-pe");
  wireApply("price-in-apply-forward-pe");

  // EPS 預測區間直接填進上下限兩個欄位，並自動補上來源說明——
  // 有 band 卻沒寫來源，Form 層會擋下來（規格要求區間必須說明出處）。
  const wireEstimate = (key: string): void => {
    document.getElementById(`price-in-apply-estimate-${key}`)?.addEventListener("click", (event) => {
      const target = event.currentTarget;
      if (!(target instanceof HTMLElement)) return;

      const low = target.dataset.low;
      const high = target.dataset.high;
      if (!low || !high) return;

      const lowField = document.getElementById("price-in-eps_band_low");
      const highField = document.getElementById("price-in-eps_band_high");
      const labelField = document.getElementById("price-in-eps_band_label");
      if (lowField instanceof HTMLInputElement) lowField.value = low;
      if (highField instanceof HTMLInputElement) highField.value = high;

      if (labelField instanceof HTMLInputElement) {
        const year = target.dataset.endDate ? target.dataset.endDate.slice(0, 4) : "";
        const n = target.dataset.analysts;
        labelField.value = `Yahoo Finance 分析師預測${year ? `（截至 ${year}` : ""}${n ? `，${n} 位` : ""}${year ? "）" : ""}`;
      }
    });
  };

  wireEstimate("current");
  wireEstimate("next");

  tickerField.addEventListener("input", () => {
    const now = tickerField.value.trim().toUpperCase();
    if (now === tickerAtLastQuote) return;
    if (stampField instanceof HTMLInputElement) stampField.value = "";
    // 估值數字是上一檔股票的，代號一改立刻作廢，
    // 否則 AVGO 的畫面上會掛著 MRVL 的倍數。
    showValuation(null);
    setStatus("代號已變更，價格尚未更新", "warn");
  });
}
