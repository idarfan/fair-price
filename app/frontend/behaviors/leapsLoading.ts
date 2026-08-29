/**
 * LEAPS 推薦：抓取進度與輪詢。
 *
 * 需要的資料由掛載元素的 data attribute 傳入：root.dataset.csrf
 *
 * 稽核 H-3 Wave 2：原本內嵌在 app/components/leaps_recommendations/page_header.rb 的 heredoc 裡。
 */

import { str } from "./shared/json";

export function init(root: HTMLElement): void {
  const form = document.getElementById("leaps-form");
  const btn = document.getElementById("leaps-submit-btn");
  const loading = document.getElementById("leaps-loading");
  if (!(form instanceof HTMLFormElement) || !(btn instanceof HTMLButtonElement) || !loading) return;

  const inpEl = document.getElementById("leaps-symbol-input");
  const inp = inpEl instanceof HTMLInputElement ? inpEl : null;
  const strikeEl = document.getElementById("leaps-strike-input");
  const strikeInp = strikeEl instanceof HTMLInputElement ? strikeEl : null;
  const strikeErr = document.getElementById("leaps-strike-error");

  inp?.addEventListener("input", () => {
    inp.value = inp.value.toUpperCase();
    // 代號一改，先前的快照就失效——清掉履約價與錯誤訊息
    if (strikeInp) strikeInp.value = "";
    if (strikeErr) { strikeErr.classList.add("hidden"); strikeErr.textContent = ""; }
  });

  form.addEventListener("submit", (e) => {
    e.preventDefault();
    const symbol = inp ? inp.value.trim().toUpperCase() : "";
    if (!symbol) return;

    if (strikeErr) { strikeErr.classList.add("hidden"); strikeErr.textContent = ""; }
    const userStrike = strikeInp ? strikeInp.value.trim() : "";

    btn.disabled = true;
    btn.textContent = "查詢中…";
    btn.classList.add("opacity-50", "cursor-not-allowed");
    loading.classList.remove("hidden");
    loading.classList.add("flex");

    const meta = document.querySelector<HTMLMetaElement>('meta[name="csrf-token"]');
    const token = meta ? meta.content : (root.dataset["csrf"] ?? "");

    const strikeSuffix = userStrike ? `&user_strike=${encodeURIComponent(userStrike)}` : "";

    const body: { symbol: string; user_strike?: string } = { symbol };
    if (userStrike) body.user_strike = userStrike;

    fetch("/leaps/analyze", {
      method: "POST",
      headers: { "Content-Type": "application/json", "X-CSRF-Token": token },
      body: JSON.stringify(body),
    })
      .then((r) => r.json())
      .then((data: unknown) => {
        const status = str(data, "status");
        if (status === "ready") {
          window.location.href = `/leaps?symbol=${symbol}${strikeSuffix}`;
          return;
        }
        if (status === "cdp_offline") {
          window.location.href = `/leaps?symbol=${symbol}&job_status=cdp_offline${strikeSuffix}`;
          return;
        }
        if (status === "invalid_strike") {
          // 就地顯示錯誤，把表單放回可用狀態
          if (strikeErr) {
            strikeErr.textContent = str(data, "message") ?? "履約價不在有效範圍，請重新輸入。";
            strikeErr.classList.remove("hidden");
          }
          btn.disabled = false;
          btn.textContent = "查詢";
          btn.classList.remove("opacity-50", "cursor-not-allowed");
          loading.classList.add("hidden");
          loading.classList.remove("flex");
          return;
        }
        const jobId = str(data, "job_id");
        if (!jobId) {
          window.location.href = `/leaps?symbol=${symbol}&job_status=error${strikeSuffix}`;
          return;
        }
        let attempts = 0;
        const pollInterval = setInterval(() => {
          attempts++;
          if (attempts > 240) {
            clearInterval(pollInterval);
            window.location.href = `/leaps?symbol=${symbol}&job_status=error${strikeSuffix}`;
            return;
          }
          fetch(`/leaps/status?job_id=${jobId}`)
            .then((r) => r.json())
            .then((s: unknown) => {
              const st = str(s, "status");
              if (!st || st === "pending" || st === "not_found") return;
              clearInterval(pollInterval);
              window.location.href = `/leaps?symbol=${symbol}&job_status=${st}${strikeSuffix}`;
            }).catch(() => {});
        }, 2500);
      }).catch(() => {
        window.location.href = `/leaps?symbol=${symbol}&job_status=error${strikeSuffix}`;
      });
  });
}
