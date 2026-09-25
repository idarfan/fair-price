// LEAPS 垂直價差 E2E 驗收（leaps-call-spread-spec P5）。
//
// 執行：node e2e/leaps_vertical_spread.e2e.mjs
// 前提：Rails 在 localhost:3003；Playwright 用的 Chrome 在 9224 且已登入 fairprice；
//       Barchart 用的 Chrome 在 9222（會實際抓取，約 2–5 分鐘，期間勿在 LEAPS 頁查詢）。
// 證據：tmp/p5/evidence.json 與 tmp/p5/*.png。任何斷言失敗 → exit 1。
//
// 與規格字面順序的差異（皆記錄在規格狀態表）：
//  - 第 9 步（回歸）移到最前面：P0 基準擷取時 ORCL 的 LEAPS 資料已過期；第 2 步送出後資料會變新鮮，
//    頁面多出候選與 PMCC，就無法與基準比對。
//  - 第 3 步「2 秒內出現進度條」從「送出後頁面跳轉並載入完成」起算：送出會先跑既有 LEAPS 抓取才跳轉。
//  - 第 8 步直接開網址：表單送出時既有驗證會先擋下不存在的履約價（既有行為）。
import { chromium } from "playwright";
import { execFileSync } from "node:child_process";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";

const BASE = "http://localhost:3003";
const OUT = "tmp/p5";
const evidence = { started_at: new Date().toISOString(), steps: {} };
mkdirSync(OUT, { recursive: true });

function assert(cond, message) {
  if (!cond) throw new Error(`斷言失敗：${message}`);
}
function sh(script, env = {}) {
  return execFileSync("bash", ["-c", script], { encoding: "utf8", env: { ...process.env, ...env } });
}
function psql(sql) {
  return sh(`set -a; source .env; set +a; psql "$DATABASE_URL" -At -F '|' -c "$SQL"`, { SQL: sql }).trim();
}
// STALL_TIMEOUT 從 Rails 的設定常數讀，不在這裡寫死（規格功能定義 5）。
const STALL_TIMEOUT = Number(
  sh(`eval "$(rbenv init -)"; bin/rails runner 'print "STALL=#{LeapsCallChainFetcher::STALL_TIMEOUT}"' 2>/dev/null`)
    .match(/STALL=(\d+)/)[1],
);

// ── 金額：以「萬分之一」整數運算，避免浮點誤差；比對時四捨五入到分 ──
const toUnits = (s) => {
  const [i, f = ""] = String(s).split(".");
  return BigInt(i) * 10000n + BigInt((f + "0000").slice(0, 4)) * (s.startsWith("-") ? -1n : 1n);
};
const centsOf = (units) => Number((units + (units >= 0n ? 50n : -50n)) / 100n) / 100; // 萬分之一 → 元，四捨五入到分
const moneyOf = (text) => Number(text.replace(/[$,]/g, ""));

function priced(row) {
  const bid = toUnits(row.bid || "0"), ask = toUnits(row.ask || "0"), last = toUnits(row.last || "0");
  if (bid > 0n && ask > 0n) return { price: (bid + ask) / 2n, source: "mid" };
  if (last > 0n) return { price: last, source: "last" };
  return { price: null, source: null };
}

function quotesFromDb(expiry, strikes) {
  const rows = psql(`select strike, coalesce(bid,0), coalesce(ask,0), coalesce(last,0), underlying_price
                     from leaps_spread_quotes where symbol='ORCL' and expiration='${expiry}'
                     and strike in (${strikes.join(",")})`);
  const byStrike = {};
  let spot = null;
  for (const line of rows.split("\n").filter(Boolean)) {
    const [strike, bid, ask, last, u] = line.split("|");
    byStrike[Number(strike)] = { bid, ask, last };
    spot = u;
  }
  return { byStrike, spot };
}

async function readBlock(page) {
  return page.evaluate(() => {
    const f = document.getElementById("leaps_vertical_spread");
    const cards = Object.fromEntries([...f.querySelectorAll(".grid > div")].map((d) => {
      const [label, value] = [...d.querySelectorAll("p")].map((p) => p.textContent.trim());
      return [label, value];
    }));
    const opts = (name) => [...f.querySelectorAll(`select[name="${name}"] option`)]
      .map((o) => ({ value: o.value, text: o.textContent, disabled: o.disabled, selected: o.selected }));
    return {
      quoted: f.querySelector("h2 + span")?.textContent ?? null,
      long: opts("expiry"), short: opts("short_strike"), cards,
      afterHours: f.querySelector(".bg-yellow-50")?.textContent ?? null,
      error: f.querySelector(".bg-red-50")?.textContent ?? null,
      text: f.textContent,
    };
  });
}

async function waitForResult(page) {
  await page.waitForSelector("#leaps_vertical_spread [data-vs-progress]", { state: "detached", timeout: 600000 });
}

function compareWithDb(block, label) {
  const expiry = block.long.find((o) => o.selected).value;
  const kS = Number(block.short.find((o) => o.selected).value);
  const { byStrike, spot } = quotesFromDb(expiry, [100, kS]);
  assert(kS > Number(spot), `${label}：K_S ${kS} 應大於現價 ${spot}`);
  const L = priced(byStrike[100]), S = priced(byStrike[kS]);
  const dMid = L.price - S.price, width = toUnits(String(kS)) - toUnits("100");
  const expected = {
    實付淨成本: centsOf(dMid * 100n), 最大獲利: centsOf((width - dMid) * 100n),
    損益兩平: centsOf(toUnits("100") + dMid),
  };
  const shown = Object.fromEntries(Object.keys(expected).map((k) => [k, moneyOf(block.cards[k])]));
  for (const k of Object.keys(expected)) {
    assert(Math.abs(shown[k] - expected[k]) <= 0.01, `${label}：${k} 畫面 ${shown[k]} ≠ 期望 ${expected[k]}`);
  }
  const afterHours = L.source === "last" || S.source === "last";
  if (afterHours) assert(block.afterHours?.includes("盤後參考價"), `${label}：盤後應有標籤`);
  return { expiry, kS, spot, legs: { long: byStrike[100], short: byStrike[kS] }, sources: [L.source, S.source],
           dom: shown, expected, after_hours: afterHours };
}

const browser = await chromium.connectOverCDP("http://localhost:9224", { timeout: 30000 });
const page = await browser.contexts()[0].newPage();
await page.setViewportSize({ width: 1280, height: 900 });
const jsErrors = [];
page.on("pageerror", (e) => jsErrors.push(e.message));

try {
  await page.goto(`${BASE}/leaps`, { waitUntil: "load" });
  assert(!page.url().includes("/login"), "9224 的 Chrome 尚未登入 fairprice（或已閒置登出），請先到 http://localhost:3003/login 登入");

  // ── 第 9 步（提前）：既有區塊回歸，與 P0 的瀏覽器 DOM 基準比對（排除新增區塊）──
  // 遮蔽：#leaps-price-context 的內部內容是即時行情（現價、POI、52 週、當日區間），
  // 由背景 job 隨行情更新，與本功能無關；外層元素的屬性照常比對。基準與現在兩邊套同一個遮蔽。
  const MASKED_SELECTORS = ["#leaps-price-context（內部內容）"];
  const mask = (html) => html.replace(
    /(<div id="leaps-price-context"[^>]*>)[\s\S]*$/,
    (_, open) => `${open}[MASKED]`,
  );
  const regression = {};
  // --skip-regression：送出表單後 LEAPS 資料會新鮮 1 小時，這段期間無法重現 P0 基準的狀態；
  // 重跑其他步驟時略過，回歸證據沿用上一輪在正確條件下的結果（由執行者在狀態表註明）。
  const skipRegression = process.argv.includes("--skip-regression");
  for (const [name, path] of skipRegression ? [] : [["a_empty", "/leaps"], ["b_symbol_only", "/leaps?symbol=ORCL"],
                              ["c_symbol_strike", "/leaps?symbol=ORCL&user_strike=100"]]) {
    // 不能直接等 networkidle：垂直價差抓取期間每秒輪詢進度，網路不會閒置。
    await page.goto(`${BASE}${path}`, { waitUntil: "load" });
    if (await page.locator("#leaps_vertical_spread").count()) await waitForResult(page);
    await page.waitForLoadState("networkidle");
    const blocks = await page.evaluate(() => [...document.getElementById("leaps-export-root").children]
      .filter((el) => el.id !== "leaps_vertical_spread").map((el) => el.outerHTML));
    const base = readFileSync(`spec/fixtures/leaps_vertical_spread/baseline/${name}.html`, "utf8")
      .trimEnd().split("\n<!-- ===== block ===== -->\n");
    const differing = base.map((b, i) => (mask(b) === mask(blocks[i] ?? "") ? null : i)).filter((i) => i !== null);
    regression[name] = { baseline_blocks: base.length, now_blocks: blocks.length, differing,
                         masked_selectors: MASKED_SELECTORS };
    assert(base.length === blocks.length && differing.length === 0, `回歸 ${name}：區塊不同 ${JSON.stringify(differing)}`);
  }
  evidence.steps.regression = skipRegression ? { skipped: true, reason: "--skip-regression" } : regression;

  // ── 第 0 步：刪除 ORCL 的垂直價差快取（到期日清單在伺服器記憶體，30 分鐘後自動過期）──
  evidence.steps.step0 = { deleted_rows: psql("with d as (delete from leaps_spread_quotes where symbol='ORCL' returning 1) select count(*) from d") };

  // ── 第 1 步 ──
  await page.goto(`${BASE}/leaps`, { waitUntil: "load" });
  assert((await page.locator("#leaps_vertical_spread").count()) === 0, "第 1 步：不應有垂直價差區塊");
  evidence.steps.step1 = { block_present: false };

  // ── 第 2 步：照使用者操作輸入並送出 ──
  await page.waitForTimeout(1500); // 等 behaviors 初始化，否則會走原生表單送出
  await page.fill("#leaps-symbol-input", "ORCL");
  await page.fill("#leaps-strike-input", "100");
  const submittedAt = Date.now();
  await page.click("#leaps-submit-btn");
  await page.waitForURL(/\/leaps\?symbol=ORCL.*user_strike=100/, { timeout: 600000, waitUntil: "load" });
  const loadedAt = Date.now();
  evidence.steps.step2 = { url: page.url(), seconds_until_navigation: Math.round((loadedAt - submittedAt) / 1000) };

  // ── 第 3 步：進度條、停滯判定 ──
  await page.waitForSelector("#leaps_vertical_spread [data-vs-progress]", { timeout: 2000 });
  const progressShownMs = Date.now() - loadedAt;
  // 第一次輪詢（1 秒後）之前顯示的是元件的預設文字，不是抓取階段，不列入
  const PLACEHOLDER = "讀取 Barchart 報價中…";
  let lastN = -1, lastStage = "", lastChange = Date.now(), maxN = 0;
  const stages = [];
  while (await page.locator("#leaps_vertical_spread [data-vs-progress]").count()) {
    const t = (await page.locator("[data-vs-progress-text]").textContent().catch(() => "")) ?? "";
    const m = t.match(/已完成 (\d+) \/ (\d+)/);
    const stage = t.replace(/（已經過 \d+ 秒）/, "");
    if ((m && Number(m[1]) > lastN) || stage !== lastStage) {
      lastChange = Date.now();
      if (m) { lastN = Number(m[1]); maxN = Math.max(maxN, Number(m[2])); }
      if (stage !== lastStage && stage !== PLACEHOLDER) stages.push(stage);
      lastStage = stage;
    }
    assert(Date.now() - lastChange <= STALL_TIMEOUT * 1000, `第 3 步：超過 ${STALL_TIMEOUT} 秒沒有進度（停在 ${lastStage}）`);
    await page.waitForTimeout(1000);
  }
  const total = Math.round((Date.now() - loadedAt) / 1000);
  const b3 = await readBlock(page);
  const order = await page.evaluate(() => {
    const html = document.body.innerHTML;
    const pmcc = html.indexOf("PMCC黃金法則組合");
    return { frame: html.indexOf('id="leaps_vertical_spread"'), pmcc };
  });
  assert(b3.error === null, `第 3 步：不應有錯誤 ${b3.error}`);
  assert(order.pmcc < 0 || order.frame < order.pmcc, "第 3 步：區塊應在 PMCC 之前");
  assert(b3.long.length > 0 && b3.long.every((o) => o.text.includes("｜100.00｜")), "第 3 步：買入腳皆應為 100.00");
  const quotedMatch = b3.quoted?.match(/(\d{4}-\d{2}-\d{2} \d{2}:\d{2})/);
  assert(quotedMatch, "第 3 步：標題列應有報價時間");
  const quotedAt = new Date(`${quotedMatch[1].replace(" ", "T")}:00+08:00`);
  assert(Math.abs(Date.now() - quotedAt.getTime()) <= 30 * 60 * 1000, "第 3 步：報價時間應在 30 分鐘內");
  // 快取未命中的證據：第 0 步刪掉的 chain 全部重抓，N 等於實際寫入的到期日數。
  // 到期日清單存在伺服器記憶體（development 的 memory_store），psql 刪不到，可能命中快取，照實記錄。
  const writtenExpiries = Number(psql("select count(distinct expiration) from leaps_spread_quotes where symbol='ORCL'"));
  assert(maxN > 0 && maxN === writtenExpiries, `第 3 步：進度 N=${maxN} 應等於寫入的到期日數 ${writtenExpiries}`);
  const expirationsListCached = !stages.some((s) => s.startsWith("讀取到期日清單"));
  await page.locator("#leaps_vertical_spread").screenshot({ path: `${OUT}/step3_default.png` });
  evidence.steps.step3 = { progress_shown_ms: progressShownMs, total_seconds: total, N: maxN,
                           written_expiries: writtenExpiries, expirations_list_cached: expirationsListCached, stages,
                           quoted: b3.quoted, pmcc_present: order.pmcc >= 0, stall_timeout: STALL_TIMEOUT };

  // ── 第 4 步：預設組合與 DB 期望值比對 ──
  evidence.steps.step4 = compareWithDb(b3, "第 4 步");

  // ── 第 5 步：換賣出腳 ──
  const otherShort = b3.short.find((o) => !o.selected && !o.disabled);
  await page.selectOption('#leaps_vertical_spread select[name="short_strike"]', otherShort.value);
  await page.waitForFunction((v) => document.querySelector('#leaps_vertical_spread select[name="short_strike"]')?.value === v
    && !document.querySelector("#leaps_vertical_spread [data-vs-progress]"), otherShort.value, { timeout: 120000 });
  const b5 = await readBlock(page);
  await page.locator("#leaps_vertical_spread").screenshot({ path: `${OUT}/step5_changed_short.png` });
  evidence.steps.step5 = b5.error ? { note: `選到的組合無效：${b5.error}`, chosen: otherShort.value }
                                  : compareWithDb(b5, "第 5 步");

  // ── 第 6 步：換買入腳到期日 ──
  if (b3.long.filter((o) => !o.disabled).length >= 2) {
    const otherLong = b3.long.find((o) => !o.selected && !o.disabled);
    await page.selectOption('#leaps_vertical_spread select[name="expiry"]', otherLong.value);
    await page.waitForFunction((v) => document.querySelector('#leaps_vertical_spread select[name="expiry"]')?.value === v
      && !document.querySelector("#leaps_vertical_spread [data-vs-progress]"), otherLong.value, { timeout: 120000 });
    const b6 = await readBlock(page);
    const spot6 = Number(quotesFromDb(otherLong.value, [100]).spot);
    assert(JSON.stringify(b6.short.map((o) => o.value)) !== JSON.stringify(b3.short.map((o) => o.value)),
      "第 6 步：賣出腳選單應換成新到期日的選項");
    assert(b6.short.every((o) => Number(o.value) > Math.max(100, spot6)), "第 6 步：賣出腳皆應 > max(100, 現價)");
    evidence.steps.step6 = { expiry: otherLong.value, short_options: b6.short.length, ...compareWithDb(b6, "第 6 步") };
  } else {
    evidence.steps.step6 = { note: "ORCL 的 100 只有 1 個到期日" };
  }

  // ── 第 7 步：重新整理再查一次，應命中快取 ──
  const reloadAt = Date.now();
  await page.goto(`${BASE}/leaps?symbol=ORCL&user_strike=100`, { waitUntil: "load" });
  await waitForResult(page);
  const b7 = await readBlock(page);
  const cacheSeconds = (Date.now() - reloadAt) / 1000;
  assert(b7.quoted === b3.quoted, `第 7 步：報價時間應與第 3 步相同（${b7.quoted} vs ${b3.quoted}）`);
  assert(!b7.text.includes("已完成"), "第 7 步：命中快取不應出現抓取進度");
  evidence.steps.step7 = { quoted: b7.quoted, seconds_until_result: cacheSeconds };

  // ── 第 8 步：錯誤情境 ──
  await page.goto(`${BASE}/leaps?symbol=ZZZZQ&user_strike=100`, { waitUntil: "load" });
  await waitForResult(page);
  const e1 = (await readBlock(page)).error;
  assert(e1?.includes("查無股票代號 ZZZZQ"), `第 8 步：ZZZZQ 應顯示查無股票代號，實際 ${e1}`);
  await page.goto(`${BASE}/leaps?symbol=ORCL&user_strike=101.37`, { waitUntil: "load" });
  await waitForResult(page);
  const e2 = (await readBlock(page)).error;
  assert(e2?.includes("ORCL 的 LEAPS 中查無履約價 101.37；最接近的履約價："), `第 8 步：101.37 訊息不符，實際 ${e2}`);
  await page.locator("#leaps_vertical_spread").screenshot({ path: `${OUT}/step8_strike_not_found.png` });
  evidence.steps.step8 = { zzzzq: e1, strike_101_37: e2 };

  // ── 第 10 步：禁用 grep ──
  const grep = sh(`grep -cE "barchart\\.com/proxies|/api/|requests\\.(get|post)|httpx|urllib|page\\.on\\(['\\"]response|page\\.route\\(|context\\.route\\(|\\.json\\(\\)|expect_response|wait_for_response" lib/barchart_scrapers/leaps_spread_expirations_scraper.py lib/barchart_scrapers/leaps_spread_chain_scraper.py || true`);
  assert(grep.trim().split("\n").every((l) => l.endsWith(":0")), `第 10 步：禁用 grep 應為 0，實際 ${grep}`);
  evidence.steps.step10 = { forbidden_grep: grep.trim().split("\n") };

  assert(jsErrors.length === 0, `頁面 JS 錯誤：${jsErrors.join("; ")}`);
  evidence.result = "PASS";
} catch (err) {
  evidence.result = "FAIL";
  evidence.error = String(err.message ?? err);
  await page.screenshot({ path: `${OUT}/failure.png`, fullPage: true }).catch(() => {});
  process.exitCode = 1;
} finally {
  evidence.finished_at = new Date().toISOString();
  evidence.js_errors = jsErrors;
  writeFileSync(`${OUT}/evidence.json`, JSON.stringify(evidence, null, 1));
  console.log(JSON.stringify({ result: evidence.result, error: evidence.error }, null, 1));
  await page.close().catch(() => {});
  await browser.close().catch(() => {});
}
