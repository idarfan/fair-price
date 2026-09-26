/**
 * 全站 driver.js 導覽卡片可以拖曳（2026-09-26 使用者要求）。
 *
 * 做法：包裝 `window.driver.js.driver` 這個 factory，所有呼叫端（LEAPS 欄位導覽
 * tooltips.js、垂直價差、Price-In、BPUS／BCVS 表頭說明）都在點擊當下才取用它，
 * 所以只要在 behaviors.ts 安裝一次，不必逐一修改。
 *
 * - 拖曳把手：卡片標題（沒有標題時用整張卡片，但按鈕、連結、表單元件上按下不算）。
 * - 換到下一步時維持拖過的位置；導覽關閉（onDestroyed）後清除，重開回到預設位置。
 * - driver.js 先呼叫 onPopoverRender、之後才設定 left／top，捲動或縮放視窗時也會
 *   重新定位，所以用 MutationObserver 監看 style，driver 改動後再把位置套回去。
 */

interface Position {
  left: number;
  top: number;
}

interface DragState {
  pos: Position | null;
}

const DRAGGABLE_CLASS = "driver-popover-draggable";
const DRAGGED_CLASS = "driver-popover-dragged";
const NOT_A_HANDLE = "button, a, input, select, textarea";

const wrappedFactories = new WeakSet<object>();

function clamp(value: number, max: number): number {
  return Math.min(Math.max(value, 0), Math.max(max, 0));
}

function fit(wrapper: HTMLElement, pos: Position): Position {
  const rect = wrapper.getBoundingClientRect();
  return {
    left: clamp(pos.left, window.innerWidth - rect.width),
    top: clamp(pos.top, window.innerHeight - rect.height),
  };
}

function apply(wrapper: HTMLElement, pos: Position): void {
  const left = `${pos.left}px`;
  const top = `${pos.top}px`;
  // 值相同就不寫，避免 MutationObserver 自己觸發自己。
  if (wrapper.style.left !== left) wrapper.style.left = left;
  if (wrapper.style.top !== top) wrapper.style.top = top;
  if (wrapper.style.right !== "auto") wrapper.style.right = "auto";
  if (wrapper.style.bottom !== "auto") wrapper.style.bottom = "auto";
  wrapper.classList.add(DRAGGED_CLASS);
}

function keepPosition(wrapper: HTMLElement, state: DragState): void {
  const observer = new MutationObserver(() => {
    if (!wrapper.isConnected) {
      observer.disconnect();
      return;
    }
    if (state.pos) apply(wrapper, state.pos);
  });
  observer.observe(wrapper, { attributes: true, attributeFilter: ["style"] });
}

function enableDrag(
  wrapper: HTMLElement,
  handle: HTMLElement,
  state: DragState,
): void {
  wrapper.classList.add(DRAGGABLE_CLASS);

  handle.addEventListener("pointerdown", (down: Event) => {
    if (!(down instanceof MouseEvent) || down.button !== 0) return;
    if (down.target instanceof Element && down.target.closest(NOT_A_HANDLE))
      return;

    const rect = wrapper.getBoundingClientRect();
    const offsetX = down.clientX - rect.left;
    const offsetY = down.clientY - rect.top;
    down.preventDefault();

    const move = (ev: Event): void => {
      if (!(ev instanceof MouseEvent)) return;
      state.pos = fit(wrapper, {
        left: ev.clientX - offsetX,
        top: ev.clientY - offsetY,
      });
      apply(wrapper, state.pos);
    };
    const up = (): void => {
      document.removeEventListener("pointermove", move);
      document.removeEventListener("pointerup", up);
      document.removeEventListener("pointercancel", up);
    };
    document.addEventListener("pointermove", move);
    document.addEventListener("pointerup", up);
    document.addEventListener("pointercancel", up);
  });
}

function onRender(popover: DriverPopoverDom, state: DragState): void {
  const { wrapper } = popover;
  const handle =
    popover.title ??
    wrapper.querySelector<HTMLElement>(".driver-popover-title") ??
    wrapper;
  enableDrag(wrapper, handle, state);
  keepPosition(wrapper, state);
}

export function installDraggableDriver(win: Window): void {
  const original = win.driver?.js?.driver;
  if (!original || wrappedFactories.has(original)) return;

  const wrapped = (config: DriverConfig): DriverInstance => {
    const state: DragState = { pos: null };
    return original({
      ...config,
      onPopoverRender: (popover, options) => {
        config.onPopoverRender?.(popover, options);
        onRender(popover, state);
      },
      onDestroyed: (element, step, options) => {
        state.pos = null;
        config.onDestroyed?.(element, step, options);
      },
    });
  };
  wrappedFactories.add(wrapped);

  const ns = win.driver?.js;
  if (ns) ns.driver = wrapped;
}
