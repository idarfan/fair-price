import js from "@eslint/js";
import tseslint from "typescript-eslint";
import reactHooks from "eslint-plugin-react-hooks";

// 瀏覽器全域。原本沒有宣告，導致 document / window / fetch 這類全域一律被
// no-undef 判成錯誤（20 個假陽性），等於 ESLint 對前端程式碼形同虛設。
// 這裡直接列出用到的名稱，而不是引入 `globals` 套件——這個專案的 npm install
// 目前卡在 vite 的 peer dependency 衝突（vite@6 vs @vitejs/plugin-react 要 vite@8）。
const browserGlobals = {
  document: "readonly",
  window: "readonly",
  navigator: "readonly",
  location: "readonly",
  history: "readonly",
  localStorage: "readonly",
  sessionStorage: "readonly",
  console: "readonly",
  fetch: "readonly",
  Headers: "readonly",
  Request: "readonly",
  Response: "readonly",
  FormData: "readonly",
  Blob: "readonly",
  File: "readonly",
  URL: "readonly",
  URLSearchParams: "readonly",
  AbortController: "readonly",
  Image: "readonly",
  Event: "readonly",
  CustomEvent: "readonly",
  MutationObserver: "readonly",
  IntersectionObserver: "readonly",
  ResizeObserver: "readonly",
  requestAnimationFrame: "readonly",
  cancelAnimationFrame: "readonly",
  setTimeout: "readonly",
  clearTimeout: "readonly",
  setInterval: "readonly",
  clearInterval: "readonly",
  queueMicrotask: "readonly",
  getComputedStyle: "readonly",
  alert: "readonly",
  confirm: "readonly",
  HTMLElement: "readonly",
  HTMLFormElement: "readonly",
  HTMLInputElement: "readonly",
  HTMLImageElement: "readonly",
  HTMLSelectElement: "readonly",
  HTMLTextAreaElement: "readonly",
  HTMLCanvasElement: "readonly",
  HTMLAnchorElement: "readonly",
};

export default tseslint.config(
  js.configs.recommended,
  ...tseslint.configs.recommended,
  {
    // 沒有 files 限定 = 套用到所有被檢查的檔案，包含 entrypoints/application.js
    // 這種純 .js 檔，否則它們的 document / window 仍會被判成 no-undef。
    languageOptions: {
      globals: { ...browserGlobals, crypto: "readonly" },
    },
  },
  {
    plugins: {
      "react-hooks": reactHooks,
    },
    rules: {
      ...reactHooks.configs.recommended.rules,
      // Catch common issues from our lessons
      "react-hooks/rules-of-hooks": "error",
      "react-hooks/exhaustive-deps": "warn",
      // set-state-in-effect: loading/error resets at effect start are intentional
      "react-hooks/set-state-in-effect": "warn",
      // No any
      "@typescript-eslint/no-explicit-any": "error",
      // Force explicit return types on public functions
      "@typescript-eslint/explicit-module-boundary-types": "off",
    },
    files: ["app/frontend/**/*.{ts,tsx}", "stories/**/*.{ts,tsx}"],
  },
  {
    // Wave 1 從 heredoc 拆出來的 LEAPS 靜態 asset 檔（由 layout 以 <script> 直接
    // 載入，不走 Vite）。它們用到的第三方全域與 Web Speech / base64 API 原本一律被
    // no-undef 判成錯誤——跟 behaviors 當初的情況同一類假陽性。
    files: ["app/assets/javascripts/**/*.js"],
    languageOptions: {
      ecmaVersion: 2022,
      sourceType: "script",
      globals: {
        ...browserGlobals,
        btoa: "readonly",
        atob: "readonly",
        speechSynthesis: "readonly",
        SpeechSynthesisUtterance: "readonly",
        htmlToImage: "readonly",
        jspdf: "readonly",
        Chart: "readonly",
        Sortable: "readonly",
        NProgress: "readonly",
        driver: "readonly",
      },
    },
  },
  {
    // pm2 設定檔是 CommonJS，不是瀏覽器程式碼。
    files: ["*.cjs", "*.config.js"],
    languageOptions: {
      sourceType: "commonjs",
      globals: { module: "writable", require: "readonly", process: "readonly", __dirname: "readonly" },
    },
  },
  {
    // 從 Phlex heredoc 搬出來的行為模組（稽核 H-3）。內容是逐字搬移的 ES5 風格
    // vanilla JS，先求「行為完全不變」，型別化是後續獨立的一輪工作。
    // 這裡放寬 var/ES5 相關規則，但 no-undef、no-unused-vars 這些真正會抓到
    // 錯誤的規則照常生效。
    files: ["app/frontend/behaviors/**/*.js"],
    languageOptions: {
      ecmaVersion: 2022,
      sourceType: "module",
      globals: {
        ...browserGlobals,
        // 由 layout 以獨立 <script> 載入的第三方全域
        Option: "readonly",
        Audio: "readonly",
        EventSource: "readonly",
        Chart: "readonly",
        Sortable: "readonly",
        NProgress: "readonly",
        htmlToImage: "readonly",
        jspdf: "readonly",
        katex: "readonly",
      },
    },
    rules: {
      // 這批是逐字搬移的 ES5 程式碼，優先保證「行為完全不變」。
      // 下面這些是原本就存在的 ES5 慣用寫法（var 重複宣告、this 別名、
      // 空 catch），不是搬遷造成的，等型別化那一輪一起清。
      "no-unused-vars": ["warn", { args: "none", varsIgnorePattern: "^_" }],
      "no-redeclare": "warn",
      "no-empty": "warn",
      "@typescript-eslint/no-this-alias": "off",
      "@typescript-eslint/no-unused-expressions": "warn",
      // 搬遷後 ESLint 首次看得到這些程式碼，抓到三處搬遷前就存在的死碼，
      // 都已於 2026-08-29 清除：
      //   bullPutSpreads.js  function hideProgress()   — 沒有任何呼叫處
      //   bullPutSpreads.js  重複的 runCalculate()      — 被後面同名宣告覆蓋，從未執行
      //   bullCallSpreads.js var k2Bid（L378）         — 下一個分支必定覆寫
      // 剩下的 no-redeclare / no-unused-expressions 是逐字搬移的 ES5 慣用寫法，
      // 留給型別化那一輪一起處理，所以維持 warn。
      "no-useless-assignment": "warn",
      "@typescript-eslint/no-unused-vars": ["warn", { args: "none", varsIgnorePattern: "^_" }],
    },
  },
  {
    ignores: [
      // 建置產物與第三方，不是我們寫的原始碼。少了這些，`npx eslint .` 會吐出
      // 兩萬多則來自 storybook-static / vendor / venv 的雜訊，等於整個 lint
      // 閘門沒人跑得動。
      "node_modules/**",
      "public/**",
      "storybook-static/**",
      "vendor/**",
      "**/venv/**",
      "coverage/**",
      "tmp/**",
      "mcp_temp_picture/**",
      "stories/Configure.mdx",
      "stories/Button.jsx",
      "stories/Header.jsx",
      "stories/Page.jsx",
    ],
  },
);
