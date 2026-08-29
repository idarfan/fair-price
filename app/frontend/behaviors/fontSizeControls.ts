/**
 * 全站字級調整（記在 localStorage）。
 *
 * 需要的資料由掛載元素的 data attribute 傳入：root.dataset.storageKey、root.dataset.sizes
 * （可用字級由 FontSizeControlsComponent::SIZES 決定，前端不再自己寫死一份）。
 *
 * 稽核 H-3 Wave 2：原本內嵌在 app/components/fair_value/font_size_controls_component.rb 的 heredoc 裡。
 * 原本用 Ruby 插值傳進來的值，改成從掛載元素的 data attribute 讀取。
 */

/**
 * data-sizes 是伺服器送來的 JSON。專案沒有 Zod（npm install 目前卡在 vite 的
 * peer dependency 衝突），所以用手寫的 type guard 取代 `as` 強轉。
 */
function isStringArray(value: unknown): value is string[] {
  return Array.isArray(value) && value.every((v) => typeof v === "string");
}

function parseSizes(raw: string | undefined): string[] {
  if (!raw) return [];
  try {
    const parsed: unknown = JSON.parse(raw);
    return isStringArray(parsed) ? parsed : [];
  } catch {
    return [];
  }
}

export function init(root: HTMLElement): void {
  const KEY = root.dataset["storageKey"] || "fairprice:font-size";
  const ALLOWED = parseSizes(root.dataset["sizes"]);
  if (!ALLOWED.length) return;

  const container = document.getElementById("font-size-controls");
  if (!container) return;
  const btns = container.querySelectorAll<HTMLElement>(".font-size-btn");

  function updateActive(active: string): void {
    btns.forEach((b) => {
      const isActive = b.getAttribute("data-size") === active;
      b.classList.toggle("text-blue-600", isActive);
      b.classList.toggle("bg-blue-50", isActive);
      b.classList.toggle("text-gray-400", !isActive);
    });
  }

  function applySize(px: number): void {
    document.documentElement.style.fontSize = `${px}px`;
    localStorage.setItem(KEY, String(px));
    updateActive(String(px));
  }

  const stored = localStorage.getItem(KEY);
  // ALLOWED 非空已於上面確認，取中間值一定拿得到字串。
  const fallback = ALLOWED[Math.floor(ALLOWED.length / 2)] ?? ALLOWED[0] ?? "";
  updateActive(stored !== null && ALLOWED.indexOf(stored) !== -1 ? stored : fallback);

  btns.forEach((b) => {
    b.addEventListener("click", () => {
      const s = b.getAttribute("data-size");
      if (s !== null && ALLOWED.indexOf(s) !== -1) applySize(parseInt(s, 10));
    });
  });
}
