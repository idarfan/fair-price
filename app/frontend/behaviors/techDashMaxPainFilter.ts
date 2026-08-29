/**
 * 技術面儀表板：Max Pain 到期日篩選。
 *
 * 需要的資料由掛載元素的 data attribute 傳入：root.dataset.symbol
 *
 * 稽核 H-3 Wave 2：原本內嵌在 app/components/technical_dashboard/page_component.rb 的 heredoc 裡。
 */

import { csrfToken, valueOf } from "./shared/dom";
import { firstString, str } from "./shared/json";

interface Filters {
  expiration: string;
  strikes: string;
  volume_oi: string;
}

const SELECT_PREFIXES = ["mp-exp-", "mp-str-", "mp-oi-"] as const;

export function init(root: HTMLElement): void {
  const sym = root.dataset["symbol"];
  if (!sym) return;
  const base = "/technical_dashboard";

  function getFilters(): Filters {
    return {
      expiration: valueOf(`mp-exp-${sym}`),
      strikes: valueOf(`mp-str-${sym}`),
      volume_oi: valueOf(`mp-oi-${sym}`),
    };
  }

  function setLoading(on: boolean): void {
    document.getElementById(`mp-loading-${sym}`)?.classList.toggle("hidden", !on);
    const err = document.getElementById(`mp-error-${sym}`);
    if (err) { err.classList.add("hidden"); err.textContent = ""; }
    SELECT_PREFIXES.forEach((p) => {
      const s = document.getElementById(p + sym);
      if (s instanceof HTMLSelectElement) s.disabled = on;
    });
  }

  function showError(msg: string): void {
    setLoading(false);
    const err = document.getElementById(`mp-error-${sym}`);
    if (err) { err.classList.remove("hidden"); err.textContent = msg; }
  }

  function redirectWithFilters(f: Filters): void {
    const p = new URLSearchParams({
      symbol: sym!, mp_expiration: f.expiration,
      mp_strikes: f.strikes, mp_vol_oi: f.volume_oi,
    });
    window.location.href = `${base}?${p.toString()}`;
  }

  function pollJob(jobId: string, f: Filters): void {
    let attempts = 0;
    const timer = setInterval(() => {
      if (++attempts > 80) { clearInterval(timer); showError("抓取逾時，請重試"); return; }
      fetch(`${base}/status?job_id=${jobId}`)
        .then((r) => r.json())
        .then((d: unknown) => {
          const status = str(d, "status");
          if (status === "pending" || status === "not_found") return;
          clearInterval(timer);
          if (status === "success") redirectWithFilters(f);
          else if (status === "session_expired") showError("Barchart 登入已過期，請重新登入後重試");
          else showError(`抓取失敗：${firstString(d, "errors") ?? status ?? ""}`);
        }).catch(() => {});
    }, 2000);
  }

  function triggerFetch(): void {
    const f = getFilters();
    if (!f.expiration) return;
    setLoading(true);
    fetch(`${base}/fetch_max_pain`, {
      method: "POST",
      headers: { "Content-Type": "application/json", "X-CSRF-Token": csrfToken() },
      body: JSON.stringify({
        symbol: sym, expiration: f.expiration,
        strikes: f.strikes, volume_oi: f.volume_oi,
      }),
    })
      .then((r) => r.json())
      .then((d: unknown) => {
        const status = str(d, "status");
        const jobId = str(d, "job_id");
        if (status === "ready") redirectWithFilters(f);
        else if (jobId) pollJob(jobId, f);
        else if (status === "cdp_offline") {
          showError("CDP 未連線，請確認 Windows 端 Chrome 已以 --remote-debugging-port=9222 啟動後重試");
        } else showError(`請求失敗：${str(d, "error") ?? "未知錯誤"}`);
      }).catch(() => { showError("網路錯誤，請重試"); });
  }

  SELECT_PREFIXES.forEach((p) => {
    document.getElementById(p + sym)?.addEventListener("change", triggerFetch);
  });
}
