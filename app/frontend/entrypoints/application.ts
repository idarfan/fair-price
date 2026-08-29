// 全站活躍度追蹤：頁面停留時間（sendBeacon）+ 指令使用（data-track-action 委派）。
// auth-and-activity.md 階段 8/9。

import { isRecord } from "../behaviors/shared/json";

function computeReferrerPath(): string | null {
  const ref = document.referrer;
  if (!ref) return null;
  try {
    const url = new URL(ref);
    return url.origin === window.location.origin ? url.pathname : "external";
  } catch {
    return "external";
  }
}

function initPageViewTracking(): void {
  const startedAt = Date.now();
  const activityToken = crypto.randomUUID();
  const referrerPath = computeReferrerPath();
  const path = window.location.pathname;
  let sent = false;

  function sendBeacon(finalSend: boolean): void {
    const durationMs = Date.now() - startedAt;
    const payload = new FormData();
    payload.append("activity_token", activityToken);
    payload.append("path", path);
    if (referrerPath !== null) payload.append("referrer_path", referrerPath);
    payload.append("duration_ms", String(durationMs));
    navigator.sendBeacon("/track/page_view", payload);
    if (finalSend) sent = true;
  }

  document.addEventListener("visibilitychange", () => {
    if (document.visibilityState === "hidden" && !sent) sendBeacon(true);
  });
  window.addEventListener("pagehide", () => {
    if (!sent) sendBeacon(true);
  });

  // 長時間停留同頁：每 5 分鐘用同一個 activity_token 補送心跳，防資料因崩潰遺失。
  setInterval(
    () => {
      if (!sent) sendBeacon(false);
    },
    5 * 60 * 1000,
  );
}

function gatherMetadata(el: Element): Record<string, unknown> {
  const explicit = el.getAttribute("data-track-metadata");
  if (explicit) {
    try {
      const parsed: unknown = JSON.parse(explicit);
      // 只有物件才算有效 metadata；陣列與純值退回表單來源，與型別化前一致
      // （型別化前直接回傳 JSON.parse 的結果，後端只會讀物件欄位）。
      if (isRecord(parsed)) return parsed;
    } catch {
      // 落到下面的表單來源
    }
  }
  const form = el.closest("form");
  if (form) {
    return Object.fromEntries(new FormData(form).entries());
  }
  return {};
}

function trackCommand(actionName: string, metadata?: Record<string, unknown>): void {
  const payload = new FormData();
  payload.append("action_name", actionName);
  payload.append("metadata", JSON.stringify(metadata ?? {}));
  navigator.sendBeacon("/track/command", payload);
}

function initCommandTracking(): void {
  document.addEventListener("click", (e) => {
    const target = e.target;
    if (!(target instanceof Element)) return;
    const el = target.closest("[data-track-action]");
    if (!el) return;
    const action = el.getAttribute("data-track-action");
    if (action === null) return;
    trackCommand(action, gatherMetadata(el));
  });
}

window.FairPriceTrack = { command: trackCommand };

initPageViewTracking();
initCommandTracking();
