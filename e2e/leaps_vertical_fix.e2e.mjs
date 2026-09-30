// LEAPS 垂直價差修正規格 S5 端到端驗收（tasks/leaps-vertical-fix.md）。
//
// 執行：node e2e/leaps_vertical_fix.e2e.mjs
// 前提：Rails 在 localhost:3003；Playwright 用的 Chrome 在 9224 且已登入 fairprice。
// 核心用例：真實頁面、代號 SHOP、所有欄位不帶選填參數。
// 證據：tmp/s5/evidence.json 與 tmp/s5/*.png。任何斷言失敗 → exit 1。
//
// 防止報價跳動造成誤判（規格 S5）：
//  - 頁面沒有報價輪詢；唯一的定時器是「載入期間每秒查進度」，載入完成即 clearInterval
//    （leapsVerticalSpread.ts load()）。腳本在快照後記錄 progress=1 請求數，必須為 0。
//  - 所有 DOM 值在同一次 page.evaluate 讀成快照，重算只用這份快照。
//  - 不重試：Barchart 讀取失敗就直接判失敗。
import { chromium } from "playwright";
import { execFileSync } from "node:child_process";
import { mkdirSync, writeFileSync } from "node:fs";

const BASE = "http://localhost:3003";
const PATH = "/leaps?symbol=SHOP&user_strike=100";
const OUT = "tmp/s5";
const TOLERANCE = 0.01;
const LOAD_TIMEOUT_MS = 5 * 60 * 1000;
const evidence = { started_at: new Date().toISOString(), steps: {} };
mkdirSync(OUT, { recursive: true });

function assert(cond, message) {
  if (!cond) throw new Error(`斷言失敗：${message}`);
}
// 費率從設定檔讀，不在這裡寫死（規格通則 8）。
const FEE = Number(
  execFileSync(
    "bash",
    ["-c", `eval "$(rbenv init -)"; bin/rails runner 'print "FEE=#{LeapsVerticalSpreadService::Config.fee_per_contract_leg.to_s("F")}"' 2>/dev/null`],
    { encoding: "utf8" },
  ).match(/FEE=([\d.]+)/)[1],
);
const money = (text) => Number(text.replace(/[+$,]/g, ""));
const round2 = (x) => Math.round((x + Number.EPSILON) * 100) / 100;
const close = (a, b) => Math.abs(a - b) <= TOLERANCE + 1e-9;

// S1 公式（含口數與來回費用）
function recompute(p) {
  const kL = Number(p.long_strike), kS = Number(p.short_strike);
  const d = Number(p.long_price) - Number(p.short_price);
  const n = Number(p.contracts);
  const roundTrip = FEE * 2 * n * 2;
  const net = d * 100 * n;
  return {
    net_cost: round2(net),
    max_profit: round2((kS - kL) * 100 * n - net - roundTrip),
    breakeven: round2(kL + d + roundTrip / (100 * n)),
  };
}

const browser = await chromium.connectOverCDP("http://localhost:9224", { timeout: 30000 });
const page = await browser.contexts()[0].newPage();
const requests = [];
page.on("request", (r) => requests.push({ url: r.url(), at: Date.now() }));
let exitCode = 0;

try {
  // ── 1. 導航、等區塊載入（失敗不重試）──
  await page.goto(`${BASE}${PATH}`, { waitUntil: "load" });
  await page.waitForSelector("#leaps_vertical_spread [data-vs-note], #leaps_vertical_spread [data-vs-retry]",
                             { timeout: LOAD_TIMEOUT_MS });
  const failure = await page.$("#leaps_vertical_spread [data-vs-retry]");
  assert(!failure, `區塊載入失敗：${await page.textContent("#leaps_vertical_spread")}`);
  evidence.steps.url = page.url();
  await page.locator("#leaps_vertical_spread").screenshot({ path: `${OUT}/s5-loaded.png` });
  evidence.steps.screenshot = `${OUT}/s5-loaded.png`;

  // ── 2. 一次讀出快照，用 S1 公式重算 ──
  const snapshot = await page.evaluate(() => {
    const value = (key) => document.querySelector(`[data-vs-tour-anchor='${key}'] [data-vs-value]`)?.innerText;
    const row = document.querySelector("[data-vs-payoff]");
    return {
      params: JSON.parse(row.dataset.vsPayoffParams),
      shown: { net_cost: value("net_cost"), max_profit: value("max_profit"), breakeven: value("breakeven") },
      long_label: document.querySelector("select[name='expiry']").selectedOptions[0].innerText,
      short_label: document.querySelector("select[name='short_strike']").selectedOptions[0].innerText,
      quoted_at: document.querySelector("#leaps_vertical_spread h2 + span")?.innerText ?? null,
      taken_at: Date.now(),
    };
  });
  const expected = recompute(snapshot.params);
  const comparison = Object.fromEntries(Object.keys(expected).map((k) => {
    const shown = money(snapshot.shown[k]);
    return [k, { shown: snapshot.shown[k], recomputed: expected[k], diff: round2(Math.abs(shown - expected[k])), ok: close(shown, expected[k]) }];
  }));
  evidence.steps.snapshot = { ...snapshot, fee_per_contract_leg: FEE, comparison };
  for (const [k, c] of Object.entries(comparison)) assert(c.ok, `${k} 顯示 ${c.shown}，重算 ${c.recomputed}`);

  // ── 3. 平倉日 = 到期日 → 平倉損益 = 到期損益；平倉日 = 報價日、預估 200 → 平倉 < 到期 ──
  async function payoffAt(closeDate) {
    const response = page.waitForResponse((r) => r.url().includes("payoff=1") && r.url().includes(`close_date=${closeDate}`));
    await page.evaluate((date) => {
      document.querySelector("[data-vs-target-price]").value = "200";
      const input = document.querySelector("[data-vs-close-date]");
      input.value = date;
      input.dispatchEvent(new Event("input", { bubbles: true }));
    }, closeDate);
    assert((await response).ok(), `payoff 片段 HTTP ${(await response).status()}`);
    await page.waitForFunction(() => document.querySelector("[data-vs-close-pnl]"));
    return page.evaluate(() => ({
      line: document.querySelector("[data-vs-payoff-line]").innerText,
      close_pnl: document.querySelector("[data-vs-close-pnl]").innerText,
      expiry_pnl: document.querySelector("[data-vs-expiry-pnl]").innerText,
    }));
  }
  const atExpiry = await payoffAt(snapshot.params.expiry);
  assert(atExpiry.close_pnl === atExpiry.expiry_pnl, `到期日平倉 ${atExpiry.close_pnl} ≠ 到期 ${atExpiry.expiry_pnl}`);
  const atQuote = await payoffAt(snapshot.params.quote_date);
  assert(money(atQuote.close_pnl) < money(atQuote.expiry_pnl), `報價日平倉 ${atQuote.close_pnl} 應小於到期 ${atQuote.expiry_pnl}`);
  evidence.steps.close_out = { expiry_date: snapshot.params.expiry, quote_date: snapshot.params.quote_date, atExpiry, atQuote };
  await page.locator("#leaps_vertical_spread").screenshot({ path: `${OUT}/s5-payoff.png` });
  evidence.steps.screenshot_payoff = `${OUT}/s5-payoff.png`;

  // ── 報價不跳動：快照之後沒有任何進度輪詢，也沒有重取整個區塊 ──
  const after = requests.filter((r) => r.at >= snapshot.taken_at);
  evidence.steps.polling = {
    mechanism: "無報價輪詢；載入期間進度輪詢於載入完成時 clearInterval",
    progress_requests_after_snapshot: after.filter((r) => r.url.includes("progress=1")).length,
    section_reloads_after_snapshot: after.filter((r) => r.url.includes("/leaps/vertical_spread?symbol=")).length,
  };
  assert(evidence.steps.polling.progress_requests_after_snapshot === 0, "快照後仍有進度輪詢");
  assert(evidence.steps.polling.section_reloads_after_snapshot === 0, "快照後區塊被重取");
  evidence.result = "PASS";
} catch (error) {
  evidence.result = "FAIL";
  evidence.error = String(error.message ?? error);
  exitCode = 1;
} finally {
  evidence.finished_at = new Date().toISOString();
  writeFileSync(`${OUT}/evidence.json`, JSON.stringify(evidence, null, 2));
  await page.close();
  await browser.close();
  console.log(JSON.stringify({ result: evidence.result, error: evidence.error }, null, 2));
  process.exit(exitCode);
}
