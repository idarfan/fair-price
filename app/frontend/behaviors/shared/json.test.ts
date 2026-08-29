import { describe, expect, it } from "vitest";

import { arr, firstString, isRecord, num, numeric, str } from "./json";

/**
 * 這組收窄函式是 behaviors 型別化那一輪新造的抽象，取代原本散落各處的
 * `parseFloat` 與直接取值。它造成過一次真實回歸（見 tasks/lessons.md
 * 2026-08-29）：`num()` 只收 number，而 Rails 把 BigDecimal 序列化成字串，
 * 於是 IV 分析頁的 Skew Rank 整批變成「—」。
 *
 * 這裡把 `num()` 與 `numeric()` 的差別釘死——那正是當時出錯的地方。
 */

describe("isRecord", () => {
  it("只接受純物件", () => {
    expect(isRecord({})).toBe(true);
    expect(isRecord({ a: 1 })).toBe(true);
  });

  it("排除 null、陣列與純值", () => {
    expect(isRecord(null)).toBe(false);
    expect(isRecord([])).toBe(false);
    expect(isRecord([1, 2])).toBe(false);
    expect(isRecord("x")).toBe(false);
    expect(isRecord(42)).toBe(false);
    expect(isRecord(undefined)).toBe(false);
  });
});

describe("str", () => {
  it("取得字串欄位", () => {
    expect(str({ a: "hi" }, "a")).toBe("hi");
  });

  it("型別不符或來源不是物件時回 undefined", () => {
    expect(str({ a: 1 }, "a")).toBeUndefined();
    expect(str({ a: null }, "a")).toBeUndefined();
    expect(str(null, "a")).toBeUndefined();
    expect(str({}, "missing")).toBeUndefined();
  });
});

describe("num（嚴格：只收 number）", () => {
  it("取得數字欄位", () => {
    expect(num({ a: 1.5 }, "a")).toBe(1.5);
    expect(num({ a: 0 }, "a")).toBe(0);
    expect(num({ a: -3 }, "a")).toBe(-3);
  });

  it("NaN 視為缺值", () => {
    expect(num({ a: NaN }, "a")).toBeUndefined();
  });

  it("數字字串一律拒絕——這是刻意的", () => {
    // 價差頁的 fmt() 原本就用 typeof === 'number' 判斷，字串本來就顯示「—」。
    // 為了修 ivAnalysis 而放寬 num()，會改壞那邊本來正確的行為。
    expect(num({ a: "1.5" }, "a")).toBeUndefined();
    expect(num({ a: "78.87" }, "a")).toBeUndefined();
  });

  it("來源不是物件時回 undefined", () => {
    expect(num(null, "a")).toBeUndefined();
    expect(num([1], "0")).toBeUndefined();
  });
});

describe("numeric（parseFloat 語意：收 number 與數字字串）", () => {
  it("數字直接回傳", () => {
    expect(numeric({ a: 1.5 }, "a")).toBe(1.5);
    expect(numeric({ a: 0 }, "a")).toBe(0);
  });

  it("接受 Rails 把 BigDecimal 序列化成的字串", () => {
    // 這正是回歸的來源：/api/iv_analysis/watchlist 回 skew_rank: "78.87"
    expect(numeric({ skew_rank: "78.87" }, "skew_rank")).toBe(78.87);
    expect(numeric({ strike: "100.0" }, "strike")).toBe(100);
    expect(numeric({ a: "-3.35" }, "a")).toBe(-3.35);
  });

  it("與 parseFloat 一樣接受尾隨雜訊", () => {
    expect(numeric({ a: "12.5px" }, "a")).toBe(12.5);
  });

  it("無法解析的字串、NaN、非數值型別回 undefined", () => {
    expect(numeric({ a: "abc" }, "a")).toBeUndefined();
    expect(numeric({ a: "" }, "a")).toBeUndefined();
    expect(numeric({ a: NaN }, "a")).toBeUndefined();
    expect(numeric({ a: null }, "a")).toBeUndefined();
    expect(numeric({ a: true }, "a")).toBeUndefined();
    expect(numeric(null, "a")).toBeUndefined();
  });

  it("與 num() 在字串上的差異就是回歸的根因", () => {
    const payload = { skew_rank: "78.87" };
    expect(num(payload, "skew_rank")).toBeUndefined(); // 型別化後：整批變「—」
    expect(numeric(payload, "skew_rank")).toBe(78.87); // 修正後：與原本 parseFloat 一致
  });
});

describe("arr", () => {
  it("取得陣列欄位", () => {
    expect(arr({ a: [1, 2] }, "a")).toEqual([1, 2]);
  });

  it("型別不符或來源不是物件時回空陣列", () => {
    expect(arr({ a: "x" }, "a")).toEqual([]);
    expect(arr({ a: null }, "a")).toEqual([]);
    expect(arr(null, "a")).toEqual([]);
  });
});

describe("firstString", () => {
  it("取得陣列第一個字串元素", () => {
    expect(firstString({ errors: ["壞了", "第二個"] }, "errors")).toBe("壞了");
  });

  it("空陣列、首元素非字串、欄位不存在都回 undefined", () => {
    expect(firstString({ errors: [] }, "errors")).toBeUndefined();
    expect(firstString({ errors: [1] }, "errors")).toBeUndefined();
    expect(firstString({}, "errors")).toBeUndefined();
  });
});
