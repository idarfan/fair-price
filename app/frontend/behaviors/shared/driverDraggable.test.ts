import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { installDraggableDriver } from "./driverDraggable";

// 模擬 driver.js 1.6：先呼叫 onPopoverRender，再設定 wrapper 的 left/top（真實順序）。
function fakeDriver() {
  const configs: DriverConfig[] = [];
  const factory = vi.fn((config: DriverConfig): DriverInstance => {
    configs.push(config);
    return { drive: vi.fn() };
  });
  return { factory, configs };
}

function renderStep(
  config: DriverConfig,
  driverLeft = 100,
  driverTop = 200,
): HTMLElement {
  document.querySelectorAll(".driver-popover").forEach((el) => el.remove());
  const wrapper = document.createElement("div");
  wrapper.className = "driver-popover";
  const title = document.createElement("header");
  title.className = "driver-popover-title";
  title.textContent = "標題";
  const next = document.createElement("button");
  next.className = "driver-popover-next-btn";
  wrapper.append(title, next);
  // happy-dom 沒有版面計算，getBoundingClientRect 一律回 0；改成依 style 回報，
  // 等同真實瀏覽器中 position: fixed 卡片的位置（寬高 300×200）。
  wrapper.getBoundingClientRect = () => {
    const left = parseFloat(wrapper.style.left) || 0;
    const top = parseFloat(wrapper.style.top) || 0;
    return new DOMRect(left, top, 300, 200);
  };
  document.body.append(wrapper);
  config.onPopoverRender?.({ wrapper, title }, {});
  wrapper.style.left = `${driverLeft}px`;
  wrapper.style.top = `${driverTop}px`;
  return wrapper;
}

function pointer(
  target: EventTarget,
  type: string,
  x: number,
  y: number,
): void {
  target.dispatchEvent(
    new MouseEvent(type, { clientX: x, clientY: y, bubbles: true, button: 0 }),
  );
}

async function flush(): Promise<void> {
  await Promise.resolve();
  await new Promise((r) => setTimeout(r, 0));
}

describe("installDraggableDriver", () => {
  let fake: ReturnType<typeof fakeDriver>;

  beforeEach(() => {
    fake = fakeDriver();
    window.driver = { js: { driver: fake.factory } };
  });

  afterEach(() => {
    window.driver = undefined;
    document.body.innerHTML = "";
  });

  function start(config: Partial<DriverConfig> = {}): DriverConfig {
    installDraggableDriver(window);
    window.driver?.js?.driver?.({ steps: [], ...config });
    const passed = fake.configs.at(-1);
    if (!passed) throw new Error("driver.js 沒有被呼叫");
    return passed;
  }

  it("包裝 factory，原本的設定與 onPopoverRender 照常傳入", () => {
    const own = vi.fn();
    const config = start({ showProgress: true, onPopoverRender: own });
    expect(config.showProgress).toBe(true);
    renderStep(config);
    expect(own).toHaveBeenCalledOnce();
  });

  it("重複安裝不會包兩層", () => {
    installDraggableDriver(window);
    installDraggableDriver(window);
    window.driver?.js?.driver?.({ steps: [] });
    expect(fake.factory).toHaveBeenCalledOnce();
  });

  it("頁面沒有載入 driver.js 時不丟例外", () => {
    window.driver = undefined;
    expect(() => installDraggableDriver(window)).not.toThrow();
  });

  it("拖曳標題移動卡片，並標記為已拖曳（隱藏箭頭）", () => {
    const wrapper = renderStep(start());
    const title = wrapper.querySelector(".driver-popover-title");
    if (!title) throw new Error("no title");
    pointer(title, "pointerdown", 110, 210);
    pointer(document, "pointermove", 160, 260);
    pointer(document, "pointerup", 160, 260);
    expect(wrapper.style.left).toBe("150px");
    expect(wrapper.style.top).toBe("250px");
    expect(wrapper.classList.contains("driver-popover-dragged")).toBe(true);
  });

  it("按鈕上按下不會開始拖曳", () => {
    const wrapper = renderStep(start());
    const next = wrapper.querySelector(".driver-popover-next-btn");
    if (!next) throw new Error("no button");
    pointer(next, "pointerdown", 110, 210);
    pointer(document, "pointermove", 300, 400);
    pointer(document, "pointerup", 300, 400);
    expect(wrapper.style.left).toBe("100px");
    expect(wrapper.classList.contains("driver-popover-dragged")).toBe(false);
  });

  it("換到下一步時維持拖過的位置（driver 重新定位後再套回）", async () => {
    const config = start();
    const first = renderStep(config);
    const title = first.querySelector(".driver-popover-title");
    if (!title) throw new Error("no title");
    pointer(title, "pointerdown", 110, 210);
    pointer(document, "pointermove", 160, 260);
    pointer(document, "pointerup", 160, 260);

    const second = renderStep(config, 500, 20);
    await flush();
    expect(second.style.left).toBe("150px");
    expect(second.style.top).toBe("250px");
  });

  it("導覽關閉後重開，回到 driver 的預設位置", async () => {
    const own = vi.fn();
    const config = start({ onDestroyed: own });
    const first = renderStep(config);
    const title = first.querySelector(".driver-popover-title");
    if (!title) throw new Error("no title");
    pointer(title, "pointerdown", 110, 210);
    pointer(document, "pointermove", 160, 260);
    pointer(document, "pointerup", 160, 260);
    config.onDestroyed?.(undefined, {}, {});
    expect(own).toHaveBeenCalledOnce();

    const again = renderStep(config, 500, 20);
    await flush();
    expect(again.style.left).toBe("500px");
    expect(again.style.top).toBe("20px");
  });
});
