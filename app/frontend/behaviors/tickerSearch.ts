/**
 * FairValue 搜尋列：送出導向估值頁、折現率 slider 即時顯示。
 * 原本內嵌於 app/components/fair_value/search_bar_component.rb（稽核 H-3）。
 */

export function init(): void {
  const form = document.getElementById("ticker-form");
  if (!(form instanceof HTMLFormElement)) return;

  form.addEventListener("submit", (event) => {
    event.preventDefault();

    const input = document.getElementById("ticker-input");
    if (!(input instanceof HTMLInputElement)) return;

    const ticker = input.value.trim().toUpperCase();
    if (!ticker) {
      input.focus();
      return;
    }

    const discountRate = document.getElementById("dr-input");
    const rate = discountRate instanceof HTMLInputElement ? discountRate.value : "10";

    window.location.href = `/valuations/${encodeURIComponent(ticker)}?discount_rate=${rate}`;
  });

  const slider = document.getElementById("dr-input");
  if (!(slider instanceof HTMLInputElement) || slider.type !== "range") return;

  slider.addEventListener("input", () => {
    const display = document.getElementById("dr-display");
    if (display) display.textContent = `${slider.value}%`;
  });
}
