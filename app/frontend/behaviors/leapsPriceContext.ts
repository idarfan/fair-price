/**
 * LEAPS 頁三個價格情境 widget（POI / 52 週區間 / 當日區間）。
 *
 * 兩件事：
 *  1. 輪詢 /leaps/price_context，拿到 HTML 片段後整塊換掉。
 *     刻意不在這裡組 markup——版面與數字格式只在 Phlex 寫一份，
 *     TS 重寫一套必然會漂移（同 pdf_export.rb 註解的理由）。
 *  2. 記住每張卡的收摺狀態。
 *
 * ⚠️ 收摺狀態的還原必須在每次 innerHTML 換入之後重跑：卡片是新的 DOM 節點，
 * 只在 init 綁一次會在第一次輪詢成功後就失效。
 */

import { applyDataStyles } from "./shared/dataStyles";
import { str } from "./shared/json";

const POLL_INTERVAL_MS = 5000;
const MAX_ATTEMPTS = 24; // 約 2 分鐘
const STORAGE_PREFIX = "leaps-price-context:";

/**
 * 讀寫 localStorage 都要包 try/catch：無痕視窗、封鎖 site data、
 * 或瀏覽器把配額用完時會直接 throw。失敗就維持 HTML 上的預設值（展開），
 * 不能讓一個「記住收摺狀態」的便利功能把整塊 widget 弄壞。
 */
function readCollapsed(key: string): boolean | undefined {
  try {
    const v = localStorage.getItem(STORAGE_PREFIX + key);
    if (v === "0") return true;
    if (v === "1") return false;
  } catch {
    /* 讀不到就用預設值 */
  }
  return undefined;
}

function writeCollapsed(key: string, collapsed: boolean): void {
  try {
    localStorage.setItem(STORAGE_PREFIX + key, collapsed ? "0" : "1");
  } catch {
    /* 存不了就算了，不影響當下的展開/收起 */
  }
}

function bindCollapse(root: HTMLElement): void {
  root
    .querySelectorAll<HTMLDetailsElement>("details[data-pc-key]")
    .forEach((el) => {
      const key = el.dataset["pcKey"];
      if (!key) return;

      const collapsed = readCollapsed(key);
      if (collapsed !== undefined) el.open = !collapsed;

      // <details> 的狀態變更走 toggle，不是 click——點 summary 以外的方式
      // （鍵盤、程式設定 open）也要記得住。
      el.addEventListener("toggle", () => writeCollapsed(key, !el.open));
    });
}

function messageBox(text: string): HTMLDivElement {
  const box = document.createElement("div");
  box.className =
    "px-4 py-3 rounded-lg text-sm bg-amber-50 border border-amber-300 text-amber-800";
  box.textContent = text;
  return box;
}

/** 完全沒資料時才整塊換成訊息。 */
function showMessage(root: HTMLElement, text: string): void {
  root.replaceChildren(messageBox(text));
}

/**
 * 有卡片可看時只在上面補一條提示，**不要 replaceChildren**。
 * VOLAP 抓不到但當日區間有值是常態（兩條供給線獨立），用一句錯誤訊息
 * 把使用者已經看得到的卡片整塊洗掉，等於拿失敗蓋掉成功的那一半。
 */
function prependMessage(root: HTMLElement, text: string): void {
  const box = messageBox(text);
  box.classList.add("mb-3");
  root.prepend(box);
}

/**
 * 逾時／連線失敗的收尾。已經畫出卡片時只補提示，沒有卡片才整塊換掉——
 * 走 replaceChildren 會把 pending 階段夾帶回來的當日區間也一起抹掉。
 */
function timedOut(root: HTMLElement, text: string): void {
  if (root.querySelector("details[data-pc-key]")) prependMessage(root, text);
  else showMessage(root, text);
}

function applyHtml(root: HTMLElement, html: string): void {
  root.innerHTML = html;
  // CSP 擋掉 style 屬性，長條寬度與游標位置是換入 DOM 之後才由
  // dataStyles 走 CSSOM 套上的。少了這一行畫面會只有文字沒有圖。
  applyDataStyles(root);
  // 換過 DOM 之後要重綁，否則收摺記憶只對首次渲染有效。
  bindCollapse(root);
}

export function init(root: HTMLElement): void {
  const symbol = root.dataset["symbol"];
  if (!symbol) return;

  bindCollapse(root);

  // 伺服器端已經把資料畫出來了（有快照），不必再輪詢。
  // 判斷依據是「有沒有量價長條」——空卡片只有標題與訊息。
  if (root.querySelector("#leaps-poi-rows")) return;

  const userStrike = root.dataset["userStrike"] ?? "";
  const query = new URLSearchParams({ symbol });
  if (userStrike) query.set("user_strike", userStrike);

  let attempts = 0;
  // pending 可能夾帶「已經有的那半邊」HTML。只套一次：每 5 秒重刷一次 DOM
  // 會讓正在看當日區間的人一直閃，而內容其實沒變。
  let partialShown = false;

  const poll = (): void => {
    attempts += 1;
    fetch(`/leaps/price_context?${query.toString()}`, {
      headers: { Accept: "application/json" },
    })
      .then((r) => r.json())
      .then((data: unknown) => {
        const status = str(data, "status");

        const html = str(data, "html");

        // 三塊都齊了。
        if (status === "ok") {
          if (!html) return;
          applyHtml(root, html);
          return;
        }

        // 抓取走到終局，但手上已經有一半資料（多半是當日區間有、VOLAP 沒有）。
        // 換上那一半，再把「為什麼另一半沒有」補在上面，然後停止輪詢。
        if (status === "partial") {
          if (html) applyHtml(root, html);
          prependMessage(
            root,
            str(data, "message") ?? "部分價格情境資料暫時無法取得。",
          );
          return;
        }

        // 完全沒資料：整塊換成訊息才是對的。
        if (status === "error") {
          showMessage(
            root,
            str(data, "message") ?? "價格情境資料暫時無法取得。",
          );
          return;
        }

        // pending。夾帶的那半邊先畫出來，不要讓人對著三張空卡等 VOLAP。
        if (html && !partialShown) {
          applyHtml(root, html);
          partialShown = true;
        }

        if (attempts >= MAX_ATTEMPTS) {
          timedOut(root, "價格情境資料抓取逾時，請重新整理頁面再試一次。");
          return;
        }
        window.setTimeout(poll, POLL_INTERVAL_MS);
      })
      .catch(() => {
        // 網路瞬斷不該直接放棄——還在次數內就繼續等下一輪。
        if (attempts >= MAX_ATTEMPTS) {
          timedOut(root, "價格情境資料抓取失敗，請重新整理頁面再試一次。");
          return;
        }
        window.setTimeout(poll, POLL_INTERVAL_MS);
      });
  };

  poll();
}
