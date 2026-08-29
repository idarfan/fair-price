/**
 * Bull Put Spread：欄位說明 tooltip。
 *
 * 稽核 H-3 Wave 3：原本內嵌在 app/components/bull_put_spreads/page_component.rb 的 heredoc 裡。
 * 稽核 M-6：tooltip 本體與 Bull Call 那支逐字相同，已抽到 shared/colTooltip。
 * 這支頁面沒有額外的導覽行為，所以就是一行轉呼叫。
 */

import { initColTooltip, type ColExplainEntry } from "./shared/colTooltip";
import { isRecord } from "./shared/json";

/** data-config 是伺服器送來的 JSON；用 type predicate 收窄，不用 `as`。 */
function parseColExplain(raw: string | undefined): Record<string, ColExplainEntry> {
  if (!raw) return {};
  let parsed: unknown;
  try { parsed = JSON.parse(raw); } catch { return {}; }
  if (!isRecord(parsed)) return {};
  const source = parsed["colExplain"];
  if (!isRecord(source)) return {};

  const out: Record<string, ColExplainEntry> = {};
  for (const [key, value] of Object.entries(source)) {
    if (!isRecord(value)) continue;
    const { title, desc } = value;
    if (typeof title === "string" && typeof desc === "string") out[key] = { title, desc };
  }
  return out;
}

export function init(root: HTMLElement): void {
  initColTooltip({ prefix: "bpus", colExplain: parseColExplain(root.dataset["config"]) });
}
