/**
 * 兩支價差試算頁共用的欄位說明 tooltip（稽核 M-6）。
 *
 * hover 顯示深色小卡、點擊改用 driver.js 的 popover 標示該欄位。抽出前
 * bullPutTooltips 與 bullCallTooltips 的這段是逐字相同的，差別只有 tip
 * 容器的 id 前綴。
 *
 * 重要：容器 id 必須維持 `<prefix>-col-tip`——app/assets/tailwind/application.css
 * 針對 #bpus-col-tip 與 #bcvs-col-tip 各有一份樣式，而且 .tip-t 的字級不同
 * （13px vs 22px），改 id 會讓兩頁的 tooltip 樣式一起壞掉。
 */

import { closestFrom } from "./dom";

export interface ColExplainEntry {
  title: string;
  desc: string;
}

export interface ColTooltipOptions {
  prefix: string;
  colExplain: Record<string, ColExplainEntry | undefined>;
}

export interface ColTooltip {
  /** driver.js 的入口；未載入時回 undefined。供呼叫端擴充（例如 bcvs 的全頁導覽）。 */
  drv: () => ((config: DriverConfig) => DriverInstance) | undefined;
  hide: () => void;
}

export function initColTooltip(options: ColTooltipOptions): ColTooltip {
  const { prefix, colExplain } = options;

  const tip = document.createElement("div");
  tip.id = `${prefix}-col-tip`;
  tip.innerHTML = '<div class="tip-t"></div><div class="tip-b"></div>';
  document.body.appendChild(tip);
  const tT = tip.querySelector(".tip-t");
  const tB = tip.querySelector(".tip-b");

  function posTip(e: MouseEvent): void {
    let x = e.clientX + 14;
    let y = e.clientY + 12;
    const w = tip.offsetWidth || 280;
    const h = tip.offsetHeight || 100;
    if (x + w > window.innerWidth - 10) x = e.clientX - w - 10;
    if (y + h > window.innerHeight - 10) y = e.clientY - h - 10;
    tip.style.left = `${x}px`;
    tip.style.top = `${y}px`;
  }

  function hide(): void { tip.style.opacity = "0"; }

  document.addEventListener("mouseover", (e) => {
    const el = closestFrom(e, "[data-tip-key]");
    if (el) {
      const key = el.dataset["tipKey"];
      const d = key === undefined ? undefined : colExplain[key];
      if (!d) return;
      if (tT) tT.textContent = d.title;
      if (tB) tB.textContent = d.desc;
      tip.style.opacity = "1";
      posTip(e);
    } else { hide(); }
  });
  document.addEventListener("mousemove", (e) => {
    if (tip.style.opacity !== "0") posTip(e);
  });
  document.addEventListener("mouseout", (e) => {
    if (!closestFrom(e, "[data-tip-key]")) hide();
  });

  const drv = (): ((config: DriverConfig) => DriverInstance) | undefined =>
    window.driver?.js?.driver;

  document.addEventListener("click", (e) => {
    const el = closestFrom(e, "[data-tip-key]");
    const driver = drv();
    if (el && driver) {
      const key = el.dataset["tipKey"];
      const d = key === undefined ? undefined : colExplain[key];
      if (!d) return;
      hide();
      driver({
        animate: true, allowClose: true, overlayOpacity: 0.35,
        steps: [{
          element: el,
          popover: { title: d.title, description: d.desc, side: "bottom", align: "center" },
        }],
      }).drive();
    }
  });

  return { drv, hide };
}
