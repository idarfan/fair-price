import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { init } from "./priceInTour";

// Price-In 的 CSP 是 style-src 'self' + nonce，不允許 style="" 屬性：
// 導覽內文若帶 inline style，瀏覽器會擋下並在 console 報錯（每步 2 次）。
describe("priceInTour 逐步導覽內文", () => {
  let configs: DriverConfig[];

  beforeEach(() => {
    configs = [];
    window.driver = {
      js: {
        driver: vi.fn((config: DriverConfig): DriverInstance => {
          configs.push(config);
          return { drive: vi.fn() };
        }),
      },
    };
    document.body.innerHTML = `
      <div id="price-in-root">
        <div data-behavior="price-in-tour" data-read-ready="false">
          <button type="button" id="price-in-toggle-help">輸入導覽</button>
          <button type="button" id="price-in-tour-start" hidden>逐步導覽</button>
        </div>
        <div data-tour-step="1">欄位</div>
      </div>
      <script type="application/json" id="price-in-tour-data">
        [{"step": 1, "title": "EPS", "body": ["第一句 <b>不是標籤</b>", "第二句"]}]
      </script>`;
  });

  afterEach(() => {
    window.driver = undefined;
    document.body.innerHTML = "";
  });

  function start(): string {
    const root = document.querySelector<HTMLElement>(
      '[data-behavior="price-in-tour"]',
    );
    if (!root) throw new Error("no root");
    init(root);
    document.getElementById("price-in-toggle-help")?.click();
    document.getElementById("price-in-tour-start")?.click();
    const description = configs[0]?.steps[0]?.popover.description;
    if (description === undefined) throw new Error("導覽沒有啟動");
    return description;
  }

  it("一句一行，不用 inline style（改用 class）", () => {
    const html = start();
    expect(html).not.toContain("style=");
    const box = document.createElement("div");
    box.innerHTML = html;
    const lines = [...box.querySelectorAll(".pi-tour-line")].map(
      (el) => el.textContent,
    );
    expect(lines).toEqual(["第一句 <b>不是標籤</b>", "第二句"]);
  });

  it("內文照樣逐字轉義", () => {
    expect(start()).toContain("&lt;b&gt;不是標籤&lt;/b&gt;");
  });
});
