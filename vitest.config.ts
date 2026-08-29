import { defineConfig } from "vitest/config";

/**
 * 前端單元測試設定（獨立於 vite.config.ts）。
 *
 * 不共用 vite.config.ts 是因為那支會載入 vite-plugin-ruby，那個 plugin 期待
 * 跑在 Rails 的 asset pipeline 情境下，測試時只會礙事。
 *
 * environment 用 node：目前只測 behaviors/shared 底下不碰 DOM 的純函式。
 * 要測 shared/dom.ts 需要 jsdom 或 happy-dom，但本專案的 `npm install` 目前
 * 卡在 peer dependency 衝突（@vitejs/plugin-react@6 要 vite@^8，專案釘 ^6.4.1），
 * 裝不了新套件。解掉那個衝突之後再補 DOM 測試。
 */
export default defineConfig({
  test: {
    environment: "node",
    include: ["app/frontend/**/*.test.ts"],
  },
});
