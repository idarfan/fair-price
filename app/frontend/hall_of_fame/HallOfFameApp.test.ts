import { createElement } from "react";
import { act } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import HallOfFameApp, { DISCLAIMER } from "./HallOfFameApp";
import HoldingsSection, { pieSlices } from "./components/HoldingsSection";
import { parseProfile } from "./parse";
import { fmtAmount } from "./format";
import type { HoldingRow, OfficialCard } from "./types";

Reflect.set(globalThis, "IS_REACT_ACT_ENVIRONMENT", true);

const cards: OfficialCard[] = [
  {
    slug: "pelosi",
    display_name: "Nancy Pelosi",
    district: "CA11",
    title: null,
    latest_filing_date: "2026-10-02",
    ptr_count: 7,
    needs_review_count: 1,
  },
];

function holding(overrides: Partial<HoldingRow>): HoldingRow {
  return {
    id: 1,
    asset_name: "Apple Inc. (AAPL)",
    ticker: "AAPL",
    owner: "SP",
    value_label: "$1,001 - $15,000",
    value_min: 1001,
    value_max: 15000,
    unbounded: false,
    estimated: 50,
    lower: 40,
    upper: 60,
    excluded_reason: null,
    needs_review: false,
    ...overrides,
  };
}

const profileJson = {
  official: {
    slug: "pelosi",
    display_name: "Nancy Pelosi",
    district: "CA11",
    title: null,
  },
  holdings: {
    doc_id: "10075701",
    year: 2025,
    filing_date: "2026-05-15",
    as_of: "2025/12/31",
    parse_status: "needs_review",
    parse_error: "第 59 列未知金額標籤：'Undetermined'",
    pdf_url: "https://example.test/10075701.pdf",
    views: {
      all: {
        upper_note: "有無上限的區間（max 為空），上限佔比無法計算",
        excluded_count: 1,
        rows: [
          holding({
            id: 1,
            estimated: 61.2345,
            lower: 55.5,
            upper: null,
            unbounded: true,
            value_max: null,
            needs_review: true,
          }),
          holding({
            id: 2,
            asset_name: "Book Contract",
            ticker: null,
            estimated: 38.7655,
            lower: 44.5,
            upper: null,
            needs_review: true,
          }),
          holding({
            id: 3,
            asset_name: "Art of Power",
            ticker: null,
            value_label: "Undetermined",
            value_min: null,
            value_max: null,
            estimated: null,
            lower: null,
            upper: null,
            excluded_reason: "金額無法對照（'Undetermined'）",
            needs_review: true,
          }),
        ],
      },
      securities: {
        upper_note: null,
        excluded_count: 0,
        rows: [holding({ id: 1, estimated: 100, lower: 100, upper: 100 })],
      },
    },
  },
  trades: {
    since: "2025-10-18",
    rows: [
      {
        id: 9,
        tx_date: "2026-07-28",
        notified_date: "2026-07-28",
        asset_name: "Bloom Energy (BE) [OP]",
        ticker: "BE",
        owner: "SP",
        tx_type: "P",
        amount_label: "$500,001 - $1,000,000",
        amount_min: 500001,
        amount_max: 1000000,
        doc_id: "20035143",
        pdf_url: "https://example.test/20035143.pdf",
        needs_review: false,
        excluded_reason: null,
        option: {
          right: "call",
          strike: 100,
          expiration: "2027-06-17",
          contracts: "申報 100 口",
          premium: "$50.00～$100.00",
          source: "stated_contracts",
          source_label: "申報",
          calc_note: "申報 100 口；每股權利金 = …",
        },
      },
    ],
    shares: {
      purchase: [
        {
          key: "BE",
          count: 1,
          mid: 750000.5,
          unbounded: false,
          estimated: 100,
        },
      ],
      sale: [],
    },
  },
  synced_at: { index: "2026-10-17T14:36:37Z", pdf_parse: null, options: null },
};

let container: HTMLDivElement;
let root: Root;

beforeEach(() => {
  container = document.createElement("div");
  document.body.appendChild(container);
  root = createRoot(container);
});

afterEach(() => {
  act(() => root.unmount());
  container.remove();
  vi.unstubAllGlobals();
});

function click(el: Element | null | undefined) {
  if (!el) throw new Error("element not found");
  act(() => {
    el.dispatchEvent(new MouseEvent("click", { bubbles: true }));
  });
}

function buttonByText(text: string): HTMLButtonElement | undefined {
  return Array.from(container.querySelectorAll("button")).find(
    (b) => b.textContent?.trim() === text,
  );
}

describe("HallOfFameApp", () => {
  it("切換「國會議員」與「行政政要」分頁，頁尾固定顯示聲明", () => {
    act(() =>
      root.render(
        createElement(HallOfFameApp, { initialTab: "congress", cards }),
      ),
    );
    expect(container.textContent).toContain("Nancy Pelosi");
    expect(container.textContent).toContain(DISCLAIMER);

    click(buttonByText("行政政要"));
    expect(
      container.querySelector('[data-testid="executive-pending"]')?.textContent,
    ).toBe("第二期建置中");
    expect(container.textContent).not.toContain("Nancy Pelosi");

    click(buttonByText("國會議員"));
    expect(container.textContent).toContain("Nancy Pelosi");
    expect(container.textContent).toContain(DISCLAIMER);
  });

  it("點人物卡後載入 API，顯示持股與交易表（含期權欄與原始 PDF）", async () => {
    const fetchMock = vi.fn().mockResolvedValue({
      ok: true,
      json: () => Promise.resolve(profileJson),
    });
    vi.stubGlobal("fetch", fetchMock);
    act(() =>
      root.render(
        createElement(HallOfFameApp, { initialTab: "congress", cards }),
      ),
    );

    await act(async () => {
      container
        .querySelector('[data-testid="official-card"]')
        ?.dispatchEvent(new MouseEvent("click", { bubbles: true }));
    });

    expect(fetchMock).toHaveBeenCalledWith(
      "/api/v1/hall_of_fame/officials/pelosi",
    );
    expect(
      container.querySelector('[data-testid="holdings-as-of"]')?.textContent,
    ).toBe("資產截至 2025/12/31");
    const trade = container.querySelector('[data-testid="trade-row"]');
    expect(trade?.textContent).toContain("申報 100 口");
    expect(
      trade
        ?.querySelector('[data-testid="option-source"]')
        ?.getAttribute("title"),
    ).toContain("申報 100 口；每股權利金");
    expect(trade?.querySelector("a")?.getAttribute("href")).toBe(
      "https://example.test/20035143.pdf",
    );
  });
});

describe("HoldingsSection", () => {
  const profile = parseProfile(profileJson);

  it("三欄佔比並列；有無上限區間時上限欄整欄「—」並註明原因", () => {
    act(() =>
      root.render(
        createElement(HoldingsSection, { holdings: profile?.holdings ?? null }),
      ),
    );
    const first = container.querySelectorAll('[data-testid="holding-row"]')[0];
    const cells = Array.from(first?.querySelectorAll("td") ?? []).map(
      (td) => td.textContent,
    );
    expect(cells.slice(4)).toEqual(["≥ 61.23%", "55.50%", "—"]);
    expect(container.textContent).toContain(
      "上限佔比「—」：有無上限的區間（max 為空），上限佔比無法計算",
    );
    const headers = Array.from(container.querySelectorAll("th")).map(
      (th) => th.textContent,
    );
    expect(headers).toEqual(
      expect.arrayContaining([
        "估算佔比",
        "下限佔比（估算）",
        "上限佔比（估算）",
      ]),
    );
  });

  it("needs_review 加警示標記；無法對照的列照原值顯示並標「不列入佔比」", () => {
    act(() =>
      root.render(
        createElement(HoldingsSection, { holdings: profile?.holdings ?? null }),
      ),
    );
    expect(
      container
        .querySelector('[data-testid="needs-review"]')
        ?.getAttribute("title"),
    ).toContain("Undetermined");
    const rows = Array.from(
      container.querySelectorAll('[data-testid="holding-row"]'),
    );
    expect(rows).toHaveLength(3);
    expect(rows[2]?.textContent).toContain(
      "Art of Power（不列入佔比：金額無法對照（'Undetermined'））",
    );
    // P5 r1 問題 1：區間欄照申報原字串顯示，不是「—」
    expect(rows[2]?.querySelectorAll("td")[3]?.textContent).toBe(
      "Undetermined",
    );
    expect(container.textContent).toContain("1 列金額或欄位無法對照");
  });

  it("非一般區間格式的標籤照原字串顯示（None 不變成 $0 – $0）", () => {
    expect(fmtAmount("None", 0, 0)).toBe("None");
    expect(fmtAmount("Spouse/DC Over $1,000,000", 1000001, null)).toBe(
      "Spouse/DC Over $1,000,000",
    );
    expect(fmtAmount("$15.00", 15, 15)).toBe("$15.00");
    expect(fmtAmount("Undetermined", null, null)).toBe("Undetermined");
    expect(fmtAmount("$1,001 - $15,000", 1001, 15000)).toBe("$1,001 – $15,000");
    expect(fmtAmount("Over $50,000,000", 50000001, null)).toBe("≥ $50,000,001");
  });

  it("切換「僅有價證券」改用重算過分母的檢視", () => {
    act(() =>
      root.render(
        createElement(HoldingsSection, { holdings: profile?.holdings ?? null }),
      ),
    );
    click(buttonByText("僅有價證券"));
    const rows = container.querySelectorAll('[data-testid="holding-row"]');
    expect(rows).toHaveLength(1);
    expect(
      Array.from(rows[0]?.querySelectorAll("td") ?? [])
        .map((td) => td.textContent)
        .slice(4),
    ).toEqual(["100.00%", "100.00%", "100.00%"]);
  });

  it("圓餅圖取前 10 名，其餘合併為「其他」", () => {
    const rows = Array.from({ length: 12 }, (_, i) =>
      holding({ id: i, ticker: `T${i}`, estimated: 12 - i }),
    );
    const slices = pieSlices(rows);
    expect(slices).toHaveLength(11);
    expect(slices[10]).toEqual({ name: "其他", value: 3 });
  });
});
