/**
 * 股票 logo 的載入失敗遞補。
 *
 * 三個頁面（Daily Momentum 觀察清單、股價提醒、持股）原本各有一份一模一樣的
 * 實作，這裡抽成共用（同 M-6 的做法）。
 *
 * 遞補順序：parqet → data-fallback（finnhub）→ 首字母色塊。
 *
 * 用 class 切換而非 el.style：CSSOM 賦值雖然不受 CSP 限制，但元件端已經改用
 * `hidden` class 表示初始隱藏（style-src 收斂），兩邊混用會讓「到底誰蓋過誰」
 * 變得要看層疊規則才知道。
 */
export function initLogoFallback(): void {
  document.querySelectorAll<HTMLImageElement>(".stock-logo").forEach((img) => {
    img.addEventListener("error", () => {
      const fallback = img.dataset["fallback"];
      if (fallback && img.src !== fallback) {
        img.src = fallback;
        return;
      }

      img.classList.add("hidden");
      const span = img.nextElementSibling;
      if (span instanceof HTMLElement) {
        span.classList.remove("hidden");
        span.classList.add("flex");
      }
    });
  });
}
