/**
 * LEAPS 垂直價差外框的行為測試（leaps-call-spread-spec P3／P4）。
 *
 * 外框只放載入中狀態；behavior 依 data-src 取回 /leaps/vertical_spread 的片段換掉內容，
 * 選單變動重新取片段，「重試」重送上一次的請求，載入期間輪詢進度顯示「已完成 n / N」。
 * 版面與數字都在伺服器（Phlex）產生，這裡只負責搬運 HTML。
 */

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { init } from "./leapsVerticalSpread";

const LOADING = `<div data-vs-section="true"><p data-vs-progress-text="true">讀取 Barchart 報價中…</p></div>`;
const RESULT = `
  <div data-vs-section="true">
    <form data-vs-form="true" action="/leaps/vertical_spread">
      <input type="hidden" name="symbol" value="ORCL">
      <input type="hidden" name="user_strike" value="100">
      <select name="expiry"><option value="2027-10-15-m">近</option><option value="2029-01-19-m" selected>遠</option></select>
      <select name="short_strike"><option value="200.00" selected>200</option><option value="230.00">230</option></select>
    </form>
    <p>實付淨成本 $3,692.50</p>
  </div>`;
const FAILURE = `<div data-vs-section="true"><span>Barchart 讀取失敗：逾時</span><button type="button" data-vs-retry="true">重試</button></div>`;

function mountFrame(): HTMLElement {
  document.body.innerHTML = `<div id="leaps_vertical_spread" data-behavior="leaps-vertical-spread"
          data-src="/leaps/vertical_spread?symbol=ORCL&amp;user_strike=100">${LOADING}</div>`;
  return document.getElementById("leaps_vertical_spread") as HTMLElement;
}

function htmlResponse(body: string): Response {
  return new Response(body, {
    status: 200,
    headers: { "Content-Type": "text/html" },
  });
}

function fragmentCalls(fetchMock: ReturnType<typeof vi.fn>): string[] {
  return fetchMock.mock.calls
    .map((c) => String(c[0]))
    .filter((u) => !u.includes("progress=1"));
}

async function flush(): Promise<void> {
  for (let i = 0; i < 5; i++) await Promise.resolve();
}

describe("leapsVerticalSpread", () => {
  let fetchMock: ReturnType<typeof vi.fn>;

  beforeEach(() => {
    vi.useFakeTimers();
    fetchMock = vi.fn();
    vi.stubGlobal("fetch", fetchMock);
  });

  afterEach(() => {
    vi.useRealTimers();
    vi.unstubAllGlobals();
  });

  it("載入時依 data-src 取回片段並換掉外框內容", async () => {
    fetchMock.mockResolvedValue(htmlResponse(RESULT));
    const root = mountFrame();
    init(root);
    await flush();

    expect(fragmentCalls(fetchMock)).toEqual([
      "/leaps/vertical_spread?symbol=ORCL&user_strike=100",
    ]);
    expect(root.textContent).toContain("實付淨成本 $3,692.50");
  });

  it("換賣出腳：帶目前兩個選單的值重新取片段", async () => {
    fetchMock.mockResolvedValue(htmlResponse(RESULT));
    const root = mountFrame();
    init(root);
    await flush();

    const short = root.querySelector<HTMLSelectElement>(
      'select[name="short_strike"]',
    );
    if (!short) throw new Error("缺少賣出腳選單");
    short.value = "230.00";
    short.dispatchEvent(new Event("change", { bubbles: true }));
    await flush();

    const last = new URL(fragmentCalls(fetchMock).at(-1) ?? "", "http://x");
    expect(last.pathname).toBe("/leaps/vertical_spread");
    expect(last.searchParams.get("expiry")).toBe("2029-01-19-m");
    expect(last.searchParams.get("short_strike")).toBe("230.00");
  });

  it("換買入腳到期日：不帶賣出腳，讓伺服器重新套用預設值", async () => {
    fetchMock.mockResolvedValue(htmlResponse(RESULT));
    const root = mountFrame();
    init(root);
    await flush();

    const expiry = root.querySelector<HTMLSelectElement>(
      'select[name="expiry"]',
    );
    if (!expiry) throw new Error("缺少買入腳選單");
    expiry.value = "2027-10-15-m";
    expiry.dispatchEvent(new Event("change", { bubbles: true }));
    await flush();

    const last = new URL(fragmentCalls(fetchMock).at(-1) ?? "", "http://x");
    expect(last.searchParams.get("expiry")).toBe("2027-10-15-m");
    expect(last.searchParams.has("short_strike")).toBe(false);
  });

  it("重試：重送上一次的請求", async () => {
    fetchMock
      .mockResolvedValueOnce(htmlResponse(FAILURE))
      .mockResolvedValue(htmlResponse(RESULT));
    const root = mountFrame();
    init(root);
    await flush();

    root.querySelector<HTMLButtonElement>("[data-vs-retry]")?.click();
    await flush();

    expect(fragmentCalls(fetchMock)).toEqual([
      "/leaps/vertical_spread?symbol=ORCL&user_strike=100",
      "/leaps/vertical_spread?symbol=ORCL&user_strike=100",
    ]);
    expect(root.textContent).toContain("實付淨成本");
  });

  it("載入期間輪詢進度，顯示「已完成 n / N 個到期日」與經過秒數", async () => {
    let finish: (r: Response) => void = () => {};
    fetchMock.mockImplementation((url: string) =>
      url.includes("progress=1")
        ? Promise.resolve(
            new Response(
              JSON.stringify({
                state: "running",
                done: 2,
                total: 6,
                stage: "讀取 2028-01-21 chain（3/6）",
              }),
            ),
          )
        : new Promise<Response>((resolve) => {
            finish = resolve;
          }),
    );
    const root = mountFrame();
    init(root);

    await vi.advanceTimersByTimeAsync(3000);
    const text =
      root.querySelector("[data-vs-progress-text]")?.textContent ?? "";
    expect(text).toContain("已完成 2 / 6 個到期日");
    expect(text).toContain("讀取 2028-01-21 chain（3/6）");
    expect(text).toMatch(/已經過 \d+ 秒/);

    finish(htmlResponse(RESULT));
    await flush();
    const callsAfterDone = fetchMock.mock.calls.length;
    await vi.advanceTimersByTimeAsync(5000);
    expect(fetchMock.mock.calls.length).toBe(callsAfterDone);
  });

  describe("賣出腳導覽（P6）", () => {
    const steps = [
      {
        anchor: "short_leg",
        title: "賣出腳在做什麼",
        lines: [
          [
            ["最多賺 ", null],
            ["$10,767.50", "profit"],
            ["。", null],
          ],
        ],
      },
      {
        anchor: "breakeven",
        title: "損益兩平",
        lines: [[["<img src=x onerror=alert(1)>", "breakeven"]]],
      },
      { anchor: "missing", title: "錨點不在畫面上", lines: [[["略過", null]]] },
    ];
    const WITH_TOUR = `
      <div data-vs-section="true">
        <div data-vs-tour-anchor="short_leg"><button type="button" data-vs-tour="true">為什麼建議 Δ 0.30？</button></div>
        <div data-vs-tour-anchor="breakeven">$142.33</div>
        <script type="application/json" data-vs-tour-data="true">${JSON.stringify(steps)}</script>
      </div>`;

    it("點按鈕以 data island 建立導覽：錨點在區塊內、顏色片段與轉義正確、缺錨點的步驟略過", async () => {
      fetchMock.mockResolvedValue(htmlResponse(WITH_TOUR));
      const drive = vi.fn();
      const factory = vi.fn<(config: DriverConfig) => DriverInstance>(() => ({
        drive,
      }));
      vi.stubGlobal("driver", { js: { driver: factory } });
      const root = mountFrame();
      init(root);
      await flush();

      root.querySelector<HTMLButtonElement>("[data-vs-tour]")?.click();

      expect(drive).toHaveBeenCalledOnce();
      const config = factory.mock.calls[0]?.[0];
      if (!config) throw new Error("driver.js 沒有被呼叫");
      expect(config).toMatchObject({ showProgress: true, allowClose: true });
      expect(config.steps).toHaveLength(2);
      const [first, second] = config.steps;
      if (!first || !second) throw new Error("導覽步驟數不對");
      expect(first.element).toBe(
        root.querySelector('[data-vs-tour-anchor="short_leg"]'),
      );
      expect(first.popover.title).toBe("賣出腳在做什麼");
      expect(first.popover.description).toContain(
        '<span class="vs-tone-profit">$10,767.50</span>',
      );
      expect(second.popover.description).toContain("&lt;img");
      expect(second.popover.description).not.toContain("<img");
    });

    it("driver.js 沒載入時不丟例外，按鈕文字提示", async () => {
      fetchMock.mockResolvedValue(htmlResponse(WITH_TOUR));
      vi.stubGlobal("driver", undefined);
      const root = mountFrame();
      init(root);
      await flush();

      const button = root.querySelector<HTMLButtonElement>("[data-vs-tour]");
      expect(() => button?.click()).not.toThrow();
      expect(button?.textContent).toBe("導覽元件未載入");
    });
  });

  it("連線失敗：顯示讀取失敗與重試", async () => {
    fetchMock.mockRejectedValue(new Error("network"));
    const root = mountFrame();
    init(root);
    await flush();

    expect(root.textContent).toContain("Barchart 讀取失敗");
    expect(root.querySelector("[data-vs-retry]")).not.toBeNull();
  });
});
