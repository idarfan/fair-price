import { afterEach, describe, expect, it } from "vitest";

import { closestFrom, csrfToken, valueOf } from "./dom";

/**
 * behaviors 型別化時新造的 DOM 小工具（見 tasks/lessons.md 2026-08-29）。
 *
 * 這三支取代了原本散落各處的 `e.target.closest(...)`、`document.getElementById(x).value`
 * 與 CSRF meta 讀取，型別化前那些寫法在元素不存在時會直接拋 TypeError。這裡把
 * 「取不到就安靜回退」的新語意釘住——那是刻意的行為改變，不能被後人「順手修掉」。
 */

afterEach(() => {
  document.body.innerHTML = "";
  document.head.innerHTML = "";
});

describe("closestFrom", () => {
  it("從事件目標往上找到符合的祖先", () => {
    document.body.innerHTML = `
      <div id="outer" data-role="row">
        <span id="inner">點我</span>
      </div>`;
    const inner = document.getElementById("inner");
    expect(inner).not.toBeNull();

    let found: HTMLElement | null = null;
    document.addEventListener("click", (e) => {
      found = closestFrom(e, "[data-role]");
    });
    inner?.dispatchEvent(new MouseEvent("click", { bubbles: true }));

    expect(found).not.toBeNull();
    expect((found as unknown as HTMLElement).id).toBe("outer");
  });

  it("目標自己就符合時回傳自己", () => {
    document.body.innerHTML = '<button id="btn" data-role="row">x</button>';
    let found: HTMLElement | null = null;
    document.addEventListener("click", (e) => {
      found = closestFrom(e, "[data-role]");
    });
    document
      .getElementById("btn")
      ?.dispatchEvent(new MouseEvent("click", { bubbles: true }));
    expect((found as unknown as HTMLElement).id).toBe("btn");
  });

  it("找不到符合的祖先時回 null（不拋錯）", () => {
    document.body.innerHTML = '<span id="inner">x</span>';
    let found: HTMLElement | null = "sentinel" as unknown as HTMLElement;
    document.addEventListener("click", (e) => {
      found = closestFrom(e, "[data-nope]");
    });
    document
      .getElementById("inner")
      ?.dispatchEvent(new MouseEvent("click", { bubbles: true }));
    expect(found).toBeNull();
  });

  it("事件目標不是 Element 時回 null", () => {
    // Event#target 的型別是 EventTarget；document 本身就不是 Element。
    // 型別化前的 `e.target.closest(...)` 在這種事件上會拋 TypeError。
    let found: HTMLElement | null = "sentinel" as unknown as HTMLElement;
    const handler = (e: Event): void => {
      found = closestFrom(e, "*");
    };
    window.addEventListener("resize", handler);
    window.dispatchEvent(new Event("resize"));
    window.removeEventListener("resize", handler);
    expect(found).toBeNull();
  });
});

describe("valueOf", () => {
  it("讀 input 的值", () => {
    document.body.innerHTML = '<input id="a" value="42">';
    expect(valueOf("a")).toBe("42");
  });

  it("讀 select 的值", () => {
    document.body.innerHTML =
      '<select id="s"><option value="x" selected>X</option></select>';
    expect(valueOf("s")).toBe("x");
  });

  it("讀 textarea 的值", () => {
    document.body.innerHTML = '<textarea id="t">hi</textarea>';
    expect(valueOf("t")).toBe("hi");
  });

  it("元素不存在時回空字串（不拋錯）", () => {
    expect(valueOf("missing")).toBe("");
  });

  it("元素存在但不是輸入元素時回空字串", () => {
    document.body.innerHTML = '<div id="d">不是輸入框</div>';
    expect(valueOf("d")).toBe("");
  });
});

describe("csrfToken", () => {
  it("讀 meta[name=csrf-token] 的 content", () => {
    document.head.innerHTML = '<meta name="csrf-token" content="tok123">';
    expect(csrfToken()).toBe("tok123");
  });

  it("meta 不存在時回空字串——與型別化前一致", () => {
    expect(csrfToken()).toBe("");
  });
});
