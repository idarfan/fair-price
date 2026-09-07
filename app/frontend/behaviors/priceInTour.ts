/**
 * Price-In 反推工具：說明卡顯示開關。
 *
 * 頁首兩顆按鈕是布林開關，不是一次性動作：
 *  - 輸入導覽 → 八張欄位說明卡
 *  - 讀圖導覽 → 兩張「怎麼看這張圖」判讀卡
 *
 * 預設兩者皆關，畫面只留輸入框與圖表。說明卡是給看不懂的人用的，
 * 不該擋住看得懂的人。
 *
 * 第三顆「逐步導覽」按鈕只在「輸入導覽」打開後才出現：它是看完說明還想被一步步
 * 帶的人才需要的，常駐頁首會讓三顆按鈕互相搶注意力。
 *
 * 錨點不存在時自動略過該步，不中斷也不報錯：圖 B 在 eps 留空時整塊不渲染，
 * 步驟 11–13 的錨點根本不在 DOM 裡。進度指示在過濾之後由 driver.js 依實際
 * 步數重新編號，不會出現「11 / 13」讓人以為漏了幾步。
 */

import { isRecord } from "./shared/json";

interface TourStep {
  step: number;
  title: string;
  body: string[];
}

function parseSteps(raw: string | null): TourStep[] {
  if (!raw) return [];
  let parsed: unknown;
  try { parsed = JSON.parse(raw); } catch { return []; }
  if (!Array.isArray(parsed)) return [];

  const out: TourStep[] = [];
  for (const item of parsed) {
    if (!isRecord(item)) continue;
    const { step, title, body } = item;
    if (typeof step !== "number" || typeof title !== "string" || !Array.isArray(body)) continue;
    out.push({ step, title, body: body.filter((b): b is string => typeof b === "string") });
  }
  return out;
}

/** 一句一行（規格 §S4 斷句規則）。locale 已切好，這裡只負責包 block。 */
function describe(sentences: string[]): string {
  return sentences.map((s) => `<div style="line-height:1.6">${escapeHtml(s)}</div>`).join("");
}

function escapeHtml(text: string): string {
  const el = document.createElement("div");
  el.textContent = text;
  return el.innerHTML;
}

function runTour(steps: TourStep[], button: HTMLElement | null): void {
  const factory = window.driver?.js?.driver;
  if (!factory) {
    // 靜靜什麼都不做是最難查的失敗：按鈕有 hover 效果、點下去毫無反應，
    // 使用者無從判斷是自己點錯還是壞了。driver.js 由 layout 依 controller
    // 條件載入，漏掛就會走到這裡。
    // eslint-disable-next-line no-console
    console.error("[price-in] driver.js 未載入，逐步導覽無法啟動");
    if (button) button.textContent = "導覽元件未載入";
    return;
  }

  const usable = steps
    .filter((s) => document.querySelector(`[data-tour-step="${s.step}"]`) !== null)
    .map((s) => ({
      element: `[data-tour-step="${s.step}"]`,
      popover: { title: s.title, description: describe(s.body), side: "bottom", align: "center" },
    }));
  if (usable.length === 0) return;

  // 設定沿用 option-basics-lesson8.html 那份。
  factory({ animate: true, allowClose: true, overlayOpacity: 0.35, showProgress: true, steps: usable }).drive();
}

const TOGGLE_OFF = "px-3 py-2 rounded-lg border border-gray-300 bg-white text-[16px] text-gray-700 hover:bg-gray-50";
const TOGGLE_ON  = "px-3 py-2 rounded-lg border border-slate-700 bg-slate-700 text-[16px] text-white hover:bg-slate-800";

/**
 * 狀態同時寫進三個地方：
 *  - root 的 data 屬性（CSS 靠它決定卡片顯不顯示）
 *  - 按鈕底色（看得見）
 *  - aria-pressed（讀得出來——單靠顏色表達狀態對色覺障礙使用者無效）
 */
function applyToggle(button: HTMLButtonElement, root: HTMLElement, attr: string, on: boolean): void {
  root.dataset[attr] = on ? "true" : "false";
  button.setAttribute("aria-pressed", on ? "true" : "false");
  button.className = on ? TOGGLE_ON : TOGGLE_OFF;
}

export function init(root: HTMLElement): void {
  const page = document.getElementById("price-in-root");
  if (!page) return;

  const readReady = root.dataset.readReady === "true";
  const epsFieldId = root.dataset.epsFieldId ?? "price-in-eps";

  const helpBtn = document.getElementById("price-in-toggle-help");
  const readBtn = document.getElementById("price-in-toggle-reading");
  const startBtn = document.getElementById("price-in-tour-start");
  const island = document.getElementById("price-in-tour-data");
  const steps = parseSteps(island?.textContent ?? null);

  let helpOn = false;
  let readOn = false;

  if (helpBtn instanceof HTMLButtonElement) {
    helpBtn.addEventListener("click", () => {
      helpOn = !helpOn;
      applyToggle(helpBtn, page, "helpVisible", helpOn);
      if (startBtn instanceof HTMLElement) startBtn.hidden = !helpOn;
    });
  }

  startBtn?.addEventListener("click", () => { runTour(steps, startBtn); });

  if (readBtn instanceof HTMLButtonElement) {
    readBtn.addEventListener("click", () => {
      if (!readReady) {
        // 不做灰階 disabled：捲到 EPS 欄位並聚焦，直接告訴使用者缺什麼。
        // 灰掉的按鈕只會讓人猜為什麼不能點。
        const field = document.getElementById(epsFieldId);
        field?.scrollIntoView({ behavior: "smooth", block: "center" });
        if (field instanceof HTMLInputElement) field.focus({ preventScroll: true });
        return;
      }
      readOn = !readOn;
      applyToggle(readBtn, page, "readingVisible", readOn);
    });
  }
}
