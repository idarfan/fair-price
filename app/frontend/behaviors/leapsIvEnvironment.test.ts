/**
 * LEAPS IV 環境區塊（leaps-iv-environment P5）：圖表資料解析與「第一次展開才畫」。
 */

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import {
  init,
  parseBarchartSeries,
  parseTermPoints,
  targetLine,
} from "./leapsIvEnvironment";

describe("parseTermPoints", () => {
  it("只收 x、y 都是數字的點；壞 JSON 回空陣列", () => {
    expect(
      parseTermPoints(
        '[{"x":405,"y":41.43},{"x":440,"y":null},{"x":587,"y":42.27}]',
      ),
    ).toEqual([
      { x: 405, y: 41.43 },
      { x: 587, y: 42.27 },
    ]);
    expect(parseTermPoints("not json")).toEqual([]);
    expect(parseTermPoints(undefined)).toEqual([]);
  });
});

describe("parseBarchartSeries", () => {
  it("缺值變 null，不變成 0", () => {
    expect(
      parseBarchartSeries(
        '{"labels":["2026-11-05","2026-11-06"],"rank":[75.1,null],"price":[353.1,375.44]}',
      ),
    ).toEqual({
      labels: ["2026-11-05", "2026-11-06"],
      rank: [75.1, null],
      price: [353.1, 375.44],
    });
  });
});

describe("targetLine", () => {
  it("540 天虛線跨整個 y 範圍", () => {
    expect(
      targetLine([
        { x: 405, y: 41 },
        { x: 587, y: 43 },
      ]),
    ).toEqual([
      { x: 540, y: 40 },
      { x: 540, y: 44 },
    ]);
    expect(targetLine([])).toEqual([]);
  });
});

describe("init", () => {
  // new Chart(...) 需要可當建構子的函式（箭頭函式不行）
  const ChartMock = vi.fn(function () {
    return { destroy: vi.fn() };
  });

  beforeEach(() => {
    vi.stubGlobal("Chart", ChartMock);
    ChartMock.mockClear();
    document.body.innerHTML = `
      <details id="leaps-iv-environment">
        <summary>IV 環境</summary>
        <canvas data-ivenv-chart="term" data-ivenv-points='[{"x":405,"y":41.4},{"x":587,"y":42.3}]'></canvas>
        <canvas data-ivenv-chart="barchart" data-ivenv-points='{"labels":["2026-11-06"],"rank":[82.44],"price":[375.44]}'></canvas>
      </details>`;
  });

  afterEach(() => vi.unstubAllGlobals());

  it("收合時不畫；第一次展開畫兩張；再展開不重畫", () => {
    const root = document.getElementById(
      "leaps-iv-environment",
    ) as HTMLDetailsElement;
    init(root);
    expect(ChartMock).not.toHaveBeenCalled();

    root.open = true;
    root.dispatchEvent(new Event("toggle"));
    expect(ChartMock).toHaveBeenCalledTimes(2);

    root.open = false;
    root.dispatchEvent(new Event("toggle"));
    root.open = true;
    root.dispatchEvent(new Event("toggle"));
    expect(ChartMock).toHaveBeenCalledTimes(2);
  });
});
