/**
 * Bull Call Spread：欄位說明 tooltip 與 9 步全頁導覽。
 *
 * 稽核 H-3 Wave 3：原本內嵌在 app/components/bull_call_spreads/page_component.rb 的 heredoc 裡。
 * 稽核 M-6：tooltip 本體與 Bull Put 那支逐字相同，已抽到 shared/colTooltip。
 * 留在這裡的只有這一頁獨有的全頁導覽。
 */

import { closestFrom } from "./shared/dom";
import { initColTooltip, type ColExplainEntry } from "./shared/colTooltip";
import { isRecord } from "./shared/json";

interface TourStep {
  el: string;
  title: string;
  desc: string;
}

interface ParsedConfig {
  colExplain: Record<string, ColExplainEntry>;
  tourSteps: TourStep[];
}

/** data-config 是伺服器送來的 JSON；用 type predicate 收窄，不用 `as`。 */
function parseConfig(raw: string | undefined): ParsedConfig {
  const empty: ParsedConfig = { colExplain: {}, tourSteps: [] };
  if (!raw) return empty;
  let parsed: unknown;
  try { parsed = JSON.parse(raw); } catch { return empty; }
  if (!isRecord(parsed)) return empty;

  const colExplain: Record<string, ColExplainEntry> = {};
  const rawExplain = parsed["colExplain"];
  if (isRecord(rawExplain)) {
    for (const [key, value] of Object.entries(rawExplain)) {
      if (!isRecord(value)) continue;
      const { title, desc } = value;
      if (typeof title === "string" && typeof desc === "string") {
        colExplain[key] = { title, desc };
      }
    }
  }

  const tourSteps: TourStep[] = [];
  const rawSteps = parsed["tourSteps"];
  if (Array.isArray(rawSteps)) {
    for (const step of rawSteps) {
      if (!isRecord(step)) continue;
      const { el, title, desc } = step;
      if (typeof el === "string" && typeof title === "string" && typeof desc === "string") {
        tourSteps.push({ el, title, desc });
      }
    }
  }

  return { colExplain, tourSteps };
}

export function init(root: HTMLElement): void {
  const cfg = parseConfig(root.dataset["config"]);
  const tip = initColTooltip({ prefix: "bcvs", colExplain: cfg.colExplain });

  // bcvs.md §導覽與欄位說明規範 B：9 步全頁導覽——步驟數固定 9，
  // 頁面當下不存在的元素直接 filter 掉（不強制報錯），任何階段都能點。
  //
  // 抽出共用核心前，這段是接在欄位 popover 的 else 分支後面（前者以 return
  // 收尾）。改成獨立的 click listener 之後兩者互不干擾：共用核心只處理
  // [data-tip-key]，這裡只處理 #bcvs-tour-btn，同一次點擊不會同時命中。
  document.addEventListener("click", (e) => {
    if (!closestFrom(e, "#bcvs-tour-btn")) return;
    const driver = tip.drv();
    if (!driver) return;

    const steps = cfg.tourSteps
      .filter((s) => document.querySelector(s.el))
      .map((s) => ({
        element: s.el,
        popover: { title: s.title, description: s.desc, side: "bottom", align: "center" },
      }));
    if (steps.length) {
      driver({
        animate: true, allowClose: true, overlayOpacity: 0.4,
        showProgress: true, steps,
      }).drive();
    }
  });
}
