/**
 * LEAPS 價格情境卡（POI／52 週／當日區間）的輪詢行為。
 *
 * 2026-09-29 SHOP：原本「頁面上已有量價長條就不輪詢」，資料舊了也永遠不會觸發重抓；
 * 改成一律問一次 /leaps/price_context，由伺服器判斷是否超過 1 小時。
 * pending 夾帶的 HTML 內容有變（例如日線先更新好）才換上，沒變就不動 DOM，避免閃爍。
 */

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { init } from "./leapsPriceContext";

const STALE_CARDS = `<div id="leaps-poi-rows">舊的 POI</div><p>當日區間 2026-09-10</p>`;

function mount(inner: string): HTMLElement {
  document.body.innerHTML = `<div id="leaps-price-context" data-behavior="leaps-price-context"
      data-symbol="SHOP" data-user-strike="100">${inner}</div>`;
  return document.getElementById("leaps-price-context") as HTMLElement;
}

function json(body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status: 200,
    headers: { "Content-Type": "application/json" },
  });
}

async function flush(): Promise<void> {
  for (let i = 0; i < 5; i++) await Promise.resolve();
}

describe("leapsPriceContext", () => {
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

  it("頁面上已經畫出卡片時，仍然向伺服器詢問一次（由伺服器判斷是否要重抓）", async () => {
    fetchMock.mockResolvedValue(json({ status: "ok", html: STALE_CARDS }));
    init(mount(STALE_CARDS));
    await flush();

    expect(fetchMock).toHaveBeenCalledTimes(1);
    expect(String(fetchMock.mock.calls[0]?.[0])).toBe(
      "/leaps/price_context?symbol=SHOP&user_strike=100",
    );
  });

  it("pending 夾帶的 HTML 內容有變才重畫，相同就不動 DOM", async () => {
    const updated = `<div id="leaps-poi-rows">舊的 POI</div><p>當日區間 2026-09-29</p>`;
    fetchMock
      .mockResolvedValueOnce(json({ status: "pending", html: updated }))
      .mockResolvedValueOnce(json({ status: "pending", html: updated }))
      .mockResolvedValueOnce(json({ status: "ok", html: updated }));
    const root = mount(STALE_CARDS);

    init(root);
    await flush();
    expect(root.textContent).toContain("2026-09-29");
    const firstNode = root.querySelector("p");

    await vi.advanceTimersByTimeAsync(5000);
    await flush();
    expect(fetchMock).toHaveBeenCalledTimes(2);
    expect(root.querySelector("p")).toBe(firstNode); // 內容相同：沒有重畫
  });

  // 2026-10-01：原本寫死 24 次 × 5 秒＝2 分鐘就放棄，但後端 job 最壞要跑約 5 分鐘
  // （兩支爬蟲各自逾時＋寬限期），前端先顯示「逾時」而 job 還在跑。
  // 上限改由伺服器帶在 data-poll-timeout-ms，跟 job 的時限同一個來源。
  describe("輪詢上限", () => {
    function mountWithBudget(ms: string | null): HTMLElement {
      const attr = ms === null ? "" : ` data-poll-timeout-ms="${ms}"`;
      document.body.innerHTML = `<div id="leaps-price-context" data-behavior="leaps-price-context"
          data-symbol="SHOP"${attr}></div>`;
      return document.getElementById("leaps-price-context") as HTMLElement;
    }

    it("照 data-poll-timeout-ms 等：超過 2 分鐘仍 pending 也不放棄", async () => {
      fetchMock.mockImplementation(() =>
        Promise.resolve(json({ status: "pending" })),
      );
      const root = mountWithBudget("330000"); // 5.5 分鐘

      init(root);
      await vi.advanceTimersByTimeAsync(4 * 60 * 1000);
      await flush();

      expect(root.textContent).not.toContain("逾時");
      expect(fetchMock.mock.calls.length).toBeGreaterThan(24);
    });

    it("超過 data-poll-timeout-ms 才顯示逾時並停止輪詢", async () => {
      fetchMock.mockImplementation(() =>
        Promise.resolve(json({ status: "pending" })),
      );
      const root = mountWithBudget("30000"); // 30 秒＝6 次

      init(root);
      await vi.advanceTimersByTimeAsync(60 * 1000);
      await flush();

      expect(root.textContent).toContain("逾時");
      expect(fetchMock).toHaveBeenCalledTimes(6);
    });

    it.each([null, "", "abc", "0", "-5"])(
      "data-poll-timeout-ms 缺漏或不合法（%s）時退回預設 2 分鐘",
      async (ms) => {
        fetchMock.mockImplementation(() =>
          Promise.resolve(json({ status: "pending" })),
        );
        const root = mountWithBudget(ms);

        init(root);
        await vi.advanceTimersByTimeAsync(5 * 60 * 1000);
        await flush();

        expect(fetchMock).toHaveBeenCalledTimes(24);
        expect(root.textContent).toContain("逾時");
      },
    );
  });
});
