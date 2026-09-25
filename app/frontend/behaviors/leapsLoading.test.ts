/**
 * LEAPS 查詢送出時的畫面狀態測試。
 *
 * 2026-09-25 ORCL：網址帶著上一次的 job_status=error，使用者按「查詢」後
 * 舊的紅色錯誤橫幅還留在畫面上，和「查詢中…」同時出現，看起來像新查詢失敗了。
 * 送出查詢時要把上一輪的狀態橫幅收起來。
 */

import { beforeEach, describe, expect, it, vi } from "vitest";
import { init } from "./leapsLoading";

const PAGE = `
  <div id="root"></div>
  <form id="leaps-form">
    <input id="leaps-symbol-input" value="ORCL">
    <input id="leaps-strike-input" value="">
    <button id="leaps-submit-btn" type="submit">查詢</button>
    <div id="leaps-loading" class="hidden"></div>
  </form>
  <div id="leaps-strike-error" class="hidden"></div>
  <div data-leaps-status-alert>❌ 抓取時發生未知錯誤，請稍後重試。</div>
  <div id="unrelated">其他區塊</div>
`;

function submit(): void {
  const form = document.getElementById("leaps-form") as HTMLFormElement;
  form.dispatchEvent(new Event("submit", { cancelable: true }));
}

describe("leapsLoading", () => {
  beforeEach(() => {
    document.body.innerHTML = PAGE;
    // 永遠不回應：只看送出當下的畫面，不讓測試走到跳轉
    vi.stubGlobal(
      "fetch",
      vi.fn(() => new Promise(() => {})),
    );
    init(document.getElementById("root") as HTMLElement);
  });

  it("送出查詢時收起上一輪的狀態橫幅", () => {
    submit();
    const alert = document.querySelector(
      "[data-leaps-status-alert]",
    ) as HTMLElement;
    expect(alert.classList.contains("hidden")).toBe(true);
  });

  it("送出查詢時顯示載入中", () => {
    submit();
    expect(
      document.getElementById("leaps-loading")?.classList.contains("hidden"),
    ).toBe(false);
  });

  it("不動其他區塊", () => {
    submit();
    expect(
      document.getElementById("unrelated")?.classList.contains("hidden"),
    ).toBe(false);
  });
});
