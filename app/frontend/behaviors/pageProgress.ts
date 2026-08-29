/**
 * 換頁進度條（NProgress）。
 *
 * 稽核 H-3：原本內嵌在 app/views/layouts/application.html.erb 的 <script> 裡。
 * NProgress 本身由 layout 以獨立 <script src> 從 CDN 載入，是全域變數
 * （型別宣告見 app/frontend/types/globals.d.ts）。
 */

import { closestFrom } from "./shared/dom";

export function init(): void {
  NProgress.configure({ showSpinner: false, speed: 300, minimum: 0.15 });

  document.addEventListener("DOMContentLoaded", () => {
    NProgress.done();

    document.addEventListener("click", (e) => {
      const link = closestFrom<HTMLAnchorElement>(e, "a[href]");
      if (!link) return;
      const href = link.getAttribute("href");
      if (!href || href.startsWith("#") || href.startsWith("javascript")
          || link.target === "_blank") return;
      NProgress.start();
      NProgress.set(0.4);
    });

    document.addEventListener("submit", () => {
      NProgress.start();
      NProgress.set(0.4);
    });
  });
}
