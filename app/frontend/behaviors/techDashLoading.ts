/**
 * 技術面儀表板：抓取進度與輪詢。
 *
 * 需要的資料由掛載元素的 data attribute 傳入：root.dataset.csrf
 *
 * 稽核 H-3 Wave 2：原本內嵌在 app/components/technical_dashboard/page_component.rb 的 heredoc 裡。
 */

import { str } from "./shared/json";

export function init(root: HTMLElement): void {
  const form = document.getElementById("td-form");
  const btn = document.getElementById("td-submit-btn");
  const loading = document.getElementById("td-loading");
  if (!(form instanceof HTMLFormElement) || !(btn instanceof HTMLButtonElement) || !loading) return;

  const inp = document.getElementById("td-symbol-input");
  const symbolInput = inp instanceof HTMLInputElement ? inp : null;
  symbolInput?.addEventListener("input", () => {
    symbolInput.value = symbolInput.value.toUpperCase();
  });

  form.addEventListener("submit", (e) => {
    e.preventDefault();
    const symbol = symbolInput ? symbolInput.value.trim().toUpperCase() : "";
    const dateEl = document.getElementById("td-date-input");
    const date = dateEl instanceof HTMLInputElement ? dateEl.value : "";
    if (!symbol) return;

    btn.disabled = true;
    btn.textContent = "分析中…";
    btn.classList.add("opacity-50", "cursor-not-allowed");
    loading.classList.remove("hidden");
    loading.classList.add("flex");

    const meta = document.querySelector<HTMLMetaElement>('meta[name="csrf-token"]');
    const token = meta ? meta.content : (root.dataset["csrf"] ?? "");

    fetch("/technical_dashboard/analyze", {
      method: "POST",
      headers: { "Content-Type": "application/json", "X-CSRF-Token": token },
      body: JSON.stringify({ symbol, date }),
    })
      .then((r) => r.json())
      .then((data: unknown) => {
        const status = str(data, "status");
        if (status === "ready") {
          window.location.href = `/technical_dashboard?symbol=${symbol}&date=${date}`;
          return;
        }
        const jobId = str(data, "job_id");
        if (!jobId) {
          let qs = `?symbol=${symbol}&date=${date}`;
          if (status) qs += `&job_status=${status}`;
          window.location.href = `/technical_dashboard${qs}`;
          return;
        }
        // 每 2.5 秒問一次，最多 60 次（150 秒）
        let attempts = 0;
        const pollInterval = setInterval(() => {
          attempts++;
          if (attempts > 60) {
            clearInterval(pollInterval);
            window.location.href =
              `/technical_dashboard?symbol=${symbol}&date=${date}&job_status=error`;
            return;
          }
          fetch(`/technical_dashboard/status?job_id=${jobId}`)
            .then((r) => r.json())
            .then((s: unknown) => {
              const st = str(s, "status");
              if (!st || st === "pending" || st === "not_found") return; // 繼續輪詢
              clearInterval(pollInterval);
              window.location.href =
                `/technical_dashboard?symbol=${symbol}&date=${date}&job_status=${st}`;
            })
            .catch(() => { /* 網路錯誤時繼續輪詢 */ });
        }, 2500);
      })
      .catch(() => {
        // 網路錯誤——退回直接導覽
        window.location.href = `/technical_dashboard?symbol=${symbol}&date=${date}`;
      });
  });
}
