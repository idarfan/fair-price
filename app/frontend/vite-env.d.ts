/// <reference types="vite/client" />

// Vite 允許直接 import CSS 當副作用；沒有這行宣告 tsc 會對
// `import 'tippy.js/dist/tippy.css'` 這類語句報 TS2882。
declare module "*.css";
