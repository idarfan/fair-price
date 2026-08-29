/**
 * behaviors 型別化用的 DOM 小工具。
 *
 * 這批模組是從 Phlex heredoc 逐字搬出來的 ES5 vanilla JS，型別化時遇到的錯誤
 * 八成集中在三件事：`getElementById` 回傳可能是 null、事件的 `target` 型別是
 * `EventTarget` 沒有 `closest`、以及 callback 參數隱含 any。這裡把前兩件收斂成
 * 幾個具名函式，讓各檔案不必到處寫 `as`（global rules 禁止 `as` 強轉）。
 */

/** 依 id 取元素，取不到回傳 null。呼叫端自行決定要不要早退。 */
export function byId<T extends HTMLElement = HTMLElement>(
  id: string,
): T | null {
  return document.getElementById(id) as T | null;
}

/**
 * 事件目標往上找最近的符合選擇器的元素。
 *
 * `Event#target` 的型別是 `EventTarget`，沒有 `closest`；而委派事件的 target
 * 也可能是文字節點。這裡一次處理掉，找不到就回 null。
 */
export function closestFrom<T extends HTMLElement = HTMLElement>(
  event: Event,
  selector: string,
): T | null {
  const target = event.target;
  if (!(target instanceof Element)) return null;
  return target.closest<T>(selector);
}

/** 事件目標本身是否落在某個選擇器內（委派事件常見的 early return）。 */
export function isWithin(event: Event, selector: string): boolean {
  return closestFrom(event, selector) !== null;
}

/** 取輸入元素的值，元素不存在或不是輸入元素時回空字串。 */
export function valueOf(id: string): string {
  const el = document.getElementById(id);
  if (
    el instanceof HTMLInputElement ||
    el instanceof HTMLSelectElement ||
    el instanceof HTMLTextAreaElement
  ) {
    return el.value;
  }
  return "";
}

/** CSRF token；取不到回空字串（與型別化前的行為一致）。 */
export function csrfToken(): string {
  const meta = document.querySelector<HTMLMetaElement>(
    'meta[name="csrf-token"]',
  );
  return meta ? meta.content : "";
}
