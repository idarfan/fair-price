/**
 * 把伺服器算好的「數值型樣式」從 data attribute 套到元素上。
 *
 * 存在的理由：CSP 的 style-src 拿掉 'unsafe-inline' 之後，HTML 的 style 屬性
 * 一律被擋，而 nonce 只對 <style> 區塊有效、對屬性無效。動態數值（百分比寬度、
 * 標記位置）又沒辦法寫成靜態 Tailwind class——Tailwind v4 的掃描器只認得
 * 原始碼裡出現過的完整字串。
 *
 * 解法是走 CSSOM：`el.style.width = ...` 這種賦值不受 CSP 限制，被擋的只有
 * 「HTML 屬性」這個形式。
 *
 * 刻意「不」做成通用的 `el.style.cssText = el.dataset.css`——那等於把 style
 * 屬性換個名字，任何能注入 HTML 的人照樣能塞任意 CSS。這裡只接受數字，
 * 而且由本檔案決定它會被組成哪一條宣告。
 */

/** 解析百分比數值；非數字或超出 0–100 一律回 null（不猜、不夾在邊界）。 */
function percent(raw: string | undefined): number | null {
  if (raw === undefined) return null;
  const n = Number(raw);
  if (!Number.isFinite(n) || n < 0 || n > 100) return null;
  return n;
}

/** 只接受 #rrggbb。任何其他形式（含 CSS 函式、url()、變數）一律拒絕。 */
function hexColor(raw: string | undefined): string | null {
  if (raw === undefined) return null;
  return /^#[0-9a-fA-F]{6}$/.test(raw) ? raw : null;
}

/**
 * 強調色：伺服器端從固定調色盤挑出的色碼，由呼叫端決定要套到哪個屬性。
 *
 * 這裡「不」提供通用的「任意屬性 = 任意值」——那等於把 style 屬性換個名字。
 * 每個 data attribute 對應一條寫死的宣告，值只接受 #rrggbb。
 */
const ACCENT_TARGETS: ReadonlyArray<readonly [string, (el: HTMLElement, hex: string) => void]> = [
  ["accentColor", (el, hex) => { el.style.color = hex; }],
  ["accentBg", (el, hex) => { el.style.backgroundColor = hex; }],
  ["accentBorderLeft", (el, hex) => { el.style.borderLeftColor = hex; }],
  ["accentBorder", (el, hex) => { el.style.borderColor = hex; }],
];

/**
 * data-bar-pct：填滿條的寬度百分比。
 * data-marker-pct：標記的水平位置百分比；data-marker-offset 可覆寫位移 px（預設 4）。
 * data-accent-color / -bg / -border / -border-left：強調色（#rrggbb）。
 */
export function applyDataStyles(root: ParentNode = document): void {
  root.querySelectorAll<HTMLElement>("[data-bar-pct]").forEach((el) => {
    const pct = percent(el.dataset["barPct"]);
    if (pct !== null) el.style.width = `${pct}%`;
  });

  root.querySelectorAll<HTMLElement>("[data-marker-pct]").forEach((el) => {
    const pct = percent(el.dataset["markerPct"]);
    if (pct === null) return;
    // 位移是為了讓標記的中心對準百分比位置，預設半個箭頭寬。
    const raw = Number(el.dataset["markerOffset"] ?? 4);
    const offset = Number.isFinite(raw) && raw >= 0 && raw <= 64 ? raw : 4;
    el.style.left = `calc(${pct}% - ${offset}px)`;
  });

  ACCENT_TARGETS.forEach(([key, apply]) => {
    const attr = `data-${key.replace(/[A-Z]/g, (c) => `-${c.toLowerCase()}`)}`;
    root.querySelectorAll<HTMLElement>(`[${attr}]`).forEach((el) => {
      const hex = hexColor(el.dataset[key]);
      if (hex !== null) apply(el, hex);
    });
  });
}
