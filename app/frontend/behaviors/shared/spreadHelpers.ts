/**
 * 兩支價差試算頁（Bull Put / Bull Call）共用的小工具（稽核 M-6）。
 *
 * 這兩頁的差異幾乎只在 DOM id 的前綴（`bpus-` / `bcvs-`）與路由，所以用
 * prefix 參數化，行為與各自原本的實作完全一致。業務流程（選腳、推薦、試算、
 * 修復模式）留在各自的模組裡，那些是真的不一樣的東西。
 */

import { csrfToken, valueOf } from "./dom";
import { str } from "./json";

export interface SpreadHelperOptions {
  /** DOM id 前綴，'bpus' 或 'bcvs' */
  prefix: string;
  /** 輪詢 job 狀態的路由（各頁的 CFG.routes.status） */
  statusPath: string;
}

export interface SpreadHelpers {
  id: (suffix: string) => HTMLElement | null;
  csrf: () => string;
  fmt: (n: unknown) => string;
  fmtLots: (perLot: unknown, lots: number) => string;
  currentLots: () => number;
  showProgress: () => void;
  pollJob: (jobId: string, onDone: (status: string) => void) => void;
}

export function createSpreadHelpers(options: SpreadHelperOptions): SpreadHelpers {
  const { prefix, statusPath } = options;

  function id(suffix: string): HTMLElement | null {
    return document.getElementById(`${prefix}-${suffix}`);
  }

  // `typeof n === 'number'` 已經排除 null（typeof null 是 'object'），所以
  // bcvs 版本原本多寫的 `&& n !== null` 永遠不會成立，合併時一併移除。
  function fmt(n: unknown): string {
    return (typeof n === "number" && !isNaN(n)) ? n.toFixed(2) : "—";
  }

  function fmtLots(perLot: unknown, lots: number): string {
    if (typeof perLot !== "number" || isNaN(perLot)) return "—";
    if (lots <= 1) return `$${fmt(perLot)}`;
    return `$${fmt(perLot)} × ${lots} = $${fmt(perLot * lots)}`;
  }

  function currentLots(): number {
    const n = parseInt(valueOf(`${prefix}-lots-input`), 10);
    return (!n || n < 1) ? 1 : n;
  }

  // 進度條只需要顯示：每條路徑在 showProgress() 之後都是整頁導覽，
  // 頁面直接被銷毀，所以沒有對應的 hideProgress。
  function showProgress(): void {
    id("progress")?.classList.remove("hidden");
  }

  // 每 2 秒問一次 job 狀態，最多 60 次（2 分鐘）後以 'error' 收尾。
  function pollJob(jobId: string, onDone: (status: string) => void): void {
    let attempts = 0;
    const timer = setInterval(() => {
      if (++attempts > 60) { clearInterval(timer); onDone("error"); return; }
      fetch(`${statusPath}?job_id=${jobId}`)
        .then((r) => r.json())
        .then((d: unknown) => {
          const status = str(d, "status");
          if (!status || status === "pending" || status === "not_found") return;
          clearInterval(timer);
          onDone(status);
        }).catch(() => {});
    }, 2000);
  }

  return { id, csrf: csrfToken, fmt, fmtLots, currentLots, showProgress, pollJob };
}
