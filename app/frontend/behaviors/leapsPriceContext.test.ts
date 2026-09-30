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
});
