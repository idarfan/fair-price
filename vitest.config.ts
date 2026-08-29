import { defineConfig } from "vitest/config";

/**
 * 前端單元測試設定（獨立於 vite.config.ts）。
 *
 * 不共用 vite.config.ts 是因為那支會載入 vite-plugin-ruby，那個 plugin 期待
 * 跑在 Rails 的 asset pipeline 情境下，測試時只會礙事。
 *
 * environment 用 happy-dom：shared/dom.ts 需要真的 DOM。
 * （原本裝不了 DOM 環境是因為 npm install 卡在 @vitejs/plugin-react@6 要
 *   vite@^8、專案卻釘 ^6.4.1 的衝突；2026-08-29 升上 vite 8 之後解除。）
 */
export default defineConfig({
  test: {
    environment: "happy-dom",
    include: ["app/frontend/**/*.test.ts"],
  },
});
