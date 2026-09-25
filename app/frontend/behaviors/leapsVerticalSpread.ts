/**
 * LEAPS 垂直價差區塊（leaps-call-spread-spec P3／P4）。
 *
 * /leaps 只輸出外框（載入中狀態 + data-src），這裡負責：
 *  1. 依 data-src 取回 /leaps/vertical_spread 的 HTML 片段，整塊換掉外框內容。
 *  2. 選單變動就帶目前的值重新取片段；換買入腳到期日時不帶賣出腳，由伺服器重新套預設值。
 *  3. 「重試」重送上一次的請求。
 *  4. 載入期間每秒輪詢進度（同一條路由帶 progress=1），顯示「已完成 n / N 個到期日」與經過秒數。
 *
 * 版面、數字與公式都只在伺服器（Phlex + LeapsVerticalSpreadService）產生，這裡不做任何計算，
 * 也不組 markup——只搬運 HTML（同 leapsPriceContext.ts 的理由）。
 */

import { num, str } from "./shared/json";

const ENDPOINT = "/leaps/vertical_spread";
const PROGRESS_INTERVAL_MS = 1000;
const FAILURE_TEXT = "Barchart 讀取失敗：連線中斷，請重試。";

export function init(root: HTMLElement): void {
  const initialSrc = root.dataset["src"];
  if (!initialSrc) return;

  const loadingHtml = root.innerHTML;
  const symbol =
    new URL(initialSrc, window.location.origin).searchParams.get("symbol") ??
    "";
  let lastUrl = initialSrc;
  let generation = 0;

  const load = (url: string): void => {
    lastUrl = url;
    generation += 1;
    const current = generation;
    const startedAt = Date.now();
    root.innerHTML = loadingHtml;

    const timer = window.setInterval(() => {
      void pollProgress(root, symbol, startedAt);
    }, PROGRESS_INTERVAL_MS);

    fetch(url, { headers: { Accept: "text/html" } })
      .then((r) => r.text())
      .then((html) => {
        if (current === generation) root.innerHTML = html;
      })
      .catch(() => {
        if (current === generation) showFailure(root);
      })
      .finally(() => window.clearInterval(timer));
  };

  root.addEventListener("change", (event) => {
    const select = event.target;
    if (!(select instanceof HTMLSelectElement)) return;
    const form = select.closest<HTMLFormElement>("form[data-vs-form]");
    if (!form) return;

    const params = new URLSearchParams();
    new FormData(form).forEach((value, key) => {
      if (typeof value === "string") params.set(key, value);
    });
    if (select.name === "expiry") params.delete("short_strike");
    load(`${ENDPOINT}?${params.toString()}`);
  });

  root.addEventListener("click", (event) => {
    const target = event.target;
    if (target instanceof Element && target.closest("[data-vs-retry]"))
      load(lastUrl);
  });

  load(initialSrc);
}

async function pollProgress(
  root: HTMLElement,
  symbol: string,
  startedAt: number,
): Promise<void> {
  const textEl = root.querySelector<HTMLElement>("[data-vs-progress-text]");
  if (!textEl) return;

  const elapsed = Math.round((Date.now() - startedAt) / 1000);
  let detail = "讀取 Barchart 報價中…";
  try {
    const res = await fetch(
      `${ENDPOINT}?${new URLSearchParams({ symbol, progress: "1" }).toString()}`,
      {
        headers: { Accept: "application/json" },
      },
    );
    const data: unknown = await res.json();
    detail = describeProgress(data) ?? detail;
  } catch {
    /* 進度只是輔助資訊，讀不到就維持原文字 */
  }
  textEl.textContent = `${detail}（已經過 ${elapsed} 秒）`;
}

function describeProgress(data: unknown): string | undefined {
  if (str(data, "state") !== "running") return undefined;

  const stage = str(data, "stage") ?? "";
  const total = num(data, "total");
  const done = num(data, "done");
  if (total === undefined || done === undefined) return stage || undefined;
  return `已完成 ${done} / ${total} 個到期日｜${stage}`;
}

function showFailure(root: HTMLElement): void {
  const box = document.createElement("div");
  box.className =
    "px-4 py-3 rounded-lg text-sm bg-red-50 border border-red-300 text-red-800 flex items-center justify-between gap-3";
  const message = document.createElement("span");
  message.textContent = FAILURE_TEXT;
  const retry = document.createElement("button");
  retry.type = "button";
  retry.dataset["vsRetry"] = "true";
  retry.className =
    "px-3 py-1 rounded-lg bg-red-600 text-white text-xs font-medium hover:bg-red-700";
  retry.textContent = "重試";
  box.append(message, retry);
  root.replaceChildren(box);
}
