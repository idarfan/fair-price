/**
 * 輪詢 CollectOptionSnapshotsJob 的執行狀態。
 *
 * `POST /collect` 從同步跑 Python 子行程改成排入背景 job（避免卡死 Puma thread），
 * 因此前端需要自己等結果。伺服器端 job 有 5 分鐘硬性 timeout，這裡的上限比它寬一點，
 * 讓 job 有機會把錯誤狀態寫進 cache 再被讀到。
 */

const POLL_INTERVAL_MS = 2000;
const MAX_WAIT_MS = 6 * 60 * 1000;

interface CollectStatus {
  status: "pending" | "success" | "error" | "expired";
  errors?: string[];
}

const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

/** 成功回傳 null；失敗回傳可直接顯示給使用者的錯誤訊息。 */
export async function waitForCollect(jobId: string): Promise<string | null> {
  const deadline = Date.now() + MAX_WAIT_MS;

  while (Date.now() < deadline) {
    await sleep(POLL_INTERVAL_MS);

    let payload: CollectStatus;
    try {
      const res = await fetch(
        `/api/v1/tracked_tickers/collect_status?job_id=${encodeURIComponent(jobId)}`,
      );
      if (!res.ok) return "資料抓取失敗，請稍後再試";
      payload = (await res.json()) as CollectStatus;
    } catch {
      // 單次網路抖動不算失敗，繼續輪詢直到逾時。
      continue;
    }

    if (payload.status === "success") return null;
    if (payload.status === "pending") continue;
    return payload.errors?.[0] ?? "資料抓取失敗";
  }

  return "抓取逾時，請稍後再試";
}
