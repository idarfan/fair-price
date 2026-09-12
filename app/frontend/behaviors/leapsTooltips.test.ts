/**
 * LEAPS 欄位／名詞說明 tooltip 的行為測試。
 *
 * 受測對象是 app/assets/javascripts/leaps_recommendations/tooltips.js——
 * 那是一支 IIFE、沒有 export，所以不直接呼叫 esc()／TIP_V()／descFor()，
 * 改成把整支載進 happy-dom 再從外部觸發事件，驗證「畫面上真的長出什麼」。
 *
 * 這樣測的好處是不必為了可測性去重構一支穩定運作的既有檔案，
 * 而且測到的是三個函式串起來的實際結果，而不是各自的回傳字串。
 *
 * 最重要的一條是轉義：tooltip 內容走 innerHTML，data-tip-value 又是
 * 從 DOM 讀回來的，一旦轉義失效就是 XSS。
 */

import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { beforeEach, describe, expect, it } from "vitest";

const SOURCE = readFileSync(
  resolve(
    __dirname,
    "../../assets/javascripts/leaps_recommendations/tooltips.js",
  ),
  "utf8",
);

/** 重新建立一份乾淨的 DOM 並載入 tooltips.js。 */
function loadTooltips(bodyHtml: string): void {
  document.body.innerHTML = bodyHtml;
  // 每次載入都會 appendChild 一個 #leaps-col-tip，先清掉舊的避免互相干擾。
  document.querySelectorAll("#leaps-col-tip").forEach((el) => el.remove());
  new Function(SOURCE)();
}

function tip(): HTMLElement {
  const el = document.getElementById("leaps-col-tip");
  if (!el) throw new Error("tooltips.js 沒有建立 #leaps-col-tip");
  return el;
}

function hover(selector: string): void {
  const el = document.querySelector(selector);
  if (!el) throw new Error(`找不到 ${selector}`);
  el.dispatchEvent(new MouseEvent("mouseover", { bubbles: true }));
}

describe("LEAPS 名詞說明 tooltip", () => {
  beforeEach(() => {
    document.body.innerHTML = "";
  });

  it("滑過名詞時顯示標題與解釋", () => {
    loadTooltips('<span id="t" data-tip-key="poi_poc">POC 117.88</span>');

    hover("#t");

    expect(tip().style.opacity).toBe("1");
    expect(tip().querySelector(".tip-t")?.textContent).toContain("POC");
    expect(tip().querySelector(".tip-b")?.textContent).toContain("成交量");
  });

  it("有 data-tip-value 時，實際數值顯示在解釋最上面那一列", () => {
    loadTooltips(
      '<span id="t" data-tip-key="poi_fvg" data-tip-value="FVG 138.22–144.49">FVG</span>',
    );

    hover("#t");

    const value = tip().querySelector(".tip-v");
    expect(value?.textContent).toBe("FVG 138.22–144.49");
    // 必須在解釋文字之前——這是它存在的理由（取代會互相遮擋的原生 title）
    const body = tip().querySelector(".tip-b");
    expect(body?.firstElementChild).toBe(value);
  });

  it("沒有 data-tip-value 時不長出數值列", () => {
    loadTooltips('<span id="t" data-tip-key="poi_overview">什麼是 POI</span>');

    hover("#t");

    expect(tip().querySelector(".tip-v")).toBeNull();
    expect(tip().querySelector(".tip-b")?.textContent).toContain("POI");
  });

  describe("轉義（tooltip 走 innerHTML，這裡失守就是 XSS）", () => {
    it("data-tip-value 裡的標籤被當成文字，不會變成真的節點", () => {
      loadTooltips(
        '<span id="t" data-tip-key="poi_poc" ' +
          'data-tip-value="<img src=x onerror=alert(1)>">POC</span>',
      );

      hover("#t");

      const value = tip().querySelector(".tip-v");
      // 三個角度各驗一次，任何一個都足以抓到轉義失效：
      expect(value?.querySelector("img")).toBeNull(); // 沒有長出節點
      expect(value?.textContent).toBe("<img src=x onerror=alert(1)>"); // 原文原樣當文字
      expect(value?.innerHTML).toContain("&lt;img"); // 實際寫進 DOM 的是轉義後的實體
      expect(value?.innerHTML).not.toContain("<img"); // 而不是真的標籤
    });

    it("引號與 & 也一併轉義", () => {
      loadTooltips(
        '<span id="t" data-tip-key="poi_poc" ' +
          "data-tip-value=\"a&amp;b &quot;c&quot; 'd'\">POC</span>",
      );

      hover("#t");

      // textContent 讀回原字串代表轉義後又被正確還原，沒有多吃也沒有少吃
      expect(tip().querySelector(".tip-v")?.textContent).toBe("a&b \"c\" 'd'");
    });

    it("注入 script 標籤不會產生 script 節點", () => {
      loadTooltips(
        '<span id="t" data-tip-key="poi_hvn" ' +
          'data-tip-value="<script>window.__pwned=1<\\/script>">HVN</span>',
      );

      hover("#t");

      expect(tip().querySelector("script")).toBeNull();
      expect(
        (window as unknown as Record<string, unknown>)["__pwned"],
      ).toBeUndefined();
    });
  });

  it("認不得的 tip key 不顯示也不丟例外", () => {
    loadTooltips('<span id="t" data-tip-key="這個key不存在">x</span>');

    expect(() => hover("#t")).not.toThrow();
    expect(tip().style.opacity).not.toBe("1");
  });

  it("滑到沒有 tip key 的地方會把 tooltip 收起來", () => {
    loadTooltips(
      '<span id="t" data-tip-key="poi_poc">POC</span><span id="plain">其他</span>',
    );
    hover("#t");
    expect(tip().style.opacity).toBe("1");

    hover("#plain");

    expect(tip().style.opacity).toBe("0");
  });
});
