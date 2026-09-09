/**
 * Price-In 匯出（規格 §S8）。
 *
 * **匯出與畫面完全脫鉤**：截的是離屏容器 `.pi-export-stage`（固定 960×540
 * CSS px），不是畫面上那張卡片。以 pixelRatio 2 捕捉 → 恆為 1920×1080，
 * 不受視窗寬度、頁面縮放、裝置 DPR 影響。同一組參數在任何機器上匯出
 * 都必須得到同一張圖，否則存檔前後無法比對。
 *
 * 用 html-to-image 而非 html2canvas：本專案 Tailwind v4 用 oklch 色彩，
 * html2canvas 不支援，html-to-image 走瀏覽器引擎的 SVG foreignObject 原生支援。
 */

const STAGE_W = 960;
const STAGE_H = 540;
const MIN_SCALE_WARNING = 0.75;

interface AuditHit {
  keyword: string;
  allowed_by: string | null;
}

function t(key: string): string {
  const el = document.getElementById("price-in-export-i18n");
  if (!el?.textContent) return key;
  try {
    const bag: unknown = JSON.parse(el.textContent);
    if (bag && typeof bag === "object" && key in bag) {
      const value = (bag as Record<string, unknown>)[key];
      if (typeof value === "string") return value;
    }
  } catch {
    /* 文案島壞掉不該擋住匯出，退回 key */
  }
  return key;
}

function stamp(): string {
  const d = new Date();
  const p = (n: number): string => String(n).padStart(2, "0");
  return `${d.getFullYear()}${p(d.getMonth() + 1)}${p(d.getDate())}`;
}

/**
 * 把畫面上的 canvas 轉成圖片填進離屏卡。
 * 在離屏容器裡另開一個 Chart.js 實例會讓同一份資料有兩個繪製路徑，
 * 兩邊版面一走鐘就會產出與畫面不一致的成品。
 */
function copyChart(stage: HTMLElement, key: string): boolean {
  const canvasId = stage.dataset.sourceCanvas;
  if (!canvasId) return false;
  const canvas = document.getElementById(canvasId);
  const img = document.getElementById(`price-in-export-${key}-img`);
  if (
    !(canvas instanceof HTMLCanvasElement) ||
    !(img instanceof HTMLImageElement)
  )
    return false;

  img.src = canvas.toDataURL("image/png");
  return true;
}

/**
 * 內容超過 540px 就整張等比縮到 fit，不裁切、不改字級、不改行距——
 * 寧可整體小一點，也不能讓判讀重點被切掉半句。
 */
function fitToStage(key: string): number {
  const fit = document.getElementById(`price-in-export-${key}-fit`);
  if (!fit) return 1;

  fit.style.transform = "";
  const height = fit.scrollHeight;
  const scale = height > STAGE_H ? STAGE_H / height : 1;
  if (scale < 1) fit.style.transform = `scale(${scale})`;
  return scale;
}

async function renderStage(stage: HTMLElement, key: string): Promise<string> {
  copyChart(stage, key);

  // 必須先等圖片解碼完成再量高度。
  //
  // 順序寫反的後果：img.src 才剛設好、還沒完成版面配置，fitToStage 量到的
  // 高度不含圖表，算出 scale = 1（不縮放）；等圖片載入後內容變高，超出
  // stage 的 540px 就被 overflow:hidden 裁掉——成品只有上半截。
  const img = document.getElementById(`price-in-export-${key}-img`);
  if (img instanceof HTMLImageElement && !img.complete) {
    await img.decode().catch(() => undefined);
  }

  const scale = fitToStage(key);
  if (scale < MIN_SCALE_WARNING) {
    // 仍照常匯出，只是告訴使用者為什麼字看起來偏小。

    console.warn(`[price-in] ${t("too_small")}（縮放 ${scale.toFixed(2)}）`);
  }

  return htmlToImage.toPng(stage, {
    pixelRatio: 2,
    width: STAGE_W,
    height: STAGE_H,
    backgroundColor: "#FFFFFF",
  });
}

function downloadPng(dataUrl: string, filename: string): void {
  const a = document.createElement("a");
  a.href = dataUrl;
  a.download = `${filename}.png`;
  document.body.appendChild(a);
  a.click();
  a.remove();
}

/**
 * PDF 用與 PNG 完全相同的點陣圖，頁面尺寸設成 1920×1080 pt，
 * 讓成品與 PNG 逐像素一致——兩種格式給出不同版面會讓人以為其中一個壞了。
 *
 * 壓縮參數 FAST 不可省：實測 LEAPS 的 2850×3160 PNG 未壓縮嵌入是 48MB，
 * 壓縮後 550KB。
 */
function downloadPdf(dataUrl: string, filename: string): void {
  const doc = new jspdf.jsPDF({
    orientation: "landscape",
    unit: "pt",
    format: [1920, 1080],
  });
  doc.addImage(dataUrl, "PNG", 0, 0, 1920, 1080, undefined, "FAST");
  doc.save(`${filename}.pdf`);
}

// ── 歸屬稽核 ────────────────────────────────────────────

/**
 * 命中機構名但不在來源白名單時跳出確認。
 *
 * 白名單走 query string，任何人都可以構造一個 URL 把字串塞進白名單讓稽核
 * 靜默放行，所以警示視窗一律列出「命中詞」與「因為什麼被放行」，
 * 讓使用者看得到判斷依據，而不是只看到一個過或不過。
 */
function auditHits(key: string): AuditHit[] {
  const el = document.getElementById(`price-in-audit-${key}`);
  if (!el?.textContent) return [];
  try {
    const parsed: unknown = JSON.parse(el.textContent);
    if (!Array.isArray(parsed)) return [];
    return parsed.flatMap((h): AuditHit[] => {
      if (!h || typeof h !== "object") return [];
      const rec = h as Record<string, unknown>;
      if (typeof rec.keyword !== "string") return [];
      return [
        {
          keyword: rec.keyword,
          allowed_by:
            typeof rec.allowed_by === "string" ? rec.allowed_by : null,
        },
      ];
    });
  } catch {
    return [];
  }
}

function confirmAttribution(key: string): boolean {
  const blocked = auditHits(key).filter((h) => h.allowed_by === null);
  if (blocked.length === 0) return true;

  const lines = blocked.map((h) => `　· ${h.keyword}`).join("\n");
  return window.confirm(
    `${t("audit_title")}\n\n${t("audit_intro")}\n\n${lines}\n\n${t("audit_hint")}`,
  );
}

// ── 掛載 ────────────────────────────────────────────────

let busy = false;

export function init(root: HTMLElement): void {
  root.addEventListener("click", (event) => {
    const target = event.target;
    if (!(target instanceof Element)) return;
    const button = target.closest("[data-price-in-export]");
    if (!(button instanceof HTMLButtonElement) || busy) return;

    const kind = button.dataset.priceInExport;
    const key = button.dataset.exportKey;
    if (!kind || !key) return;

    if (typeof htmlToImage === "undefined") {
      window.alert(t("missing_lib"));
      return;
    }
    if (kind === "pdf" && typeof jspdf === "undefined") {
      window.alert(t("missing_lib"));
      return;
    }
    if (!confirmAttribution(key)) return;

    const stage = document.getElementById(`price-in-export-${key}`);
    if (!stage) return;

    // 檔名必須含代號，否則連續匯出多檔股票會難以分辨甚至覆蓋。
    const ticker =
      (document.getElementById("price-in-ticker") as HTMLInputElement | null)
        ?.value || "UNKNOWN";
    const suffix = key.replace("_", "-");
    const filename = `price-in-${ticker.toUpperCase()}-${suffix}-${stamp()}`;

    const original = button.textContent;
    busy = true;
    button.disabled = true;
    button.textContent = t("exporting");

    void renderStage(stage, key)
      .then((dataUrl) => {
        if (kind === "pdf") downloadPdf(dataUrl, filename);
        else downloadPng(dataUrl, filename);
      })
      .catch((err: unknown) => {
        window.alert(
          `匯出失敗：${err instanceof Error ? err.message : String(err)}`,
        );
      })
      .finally(() => {
        busy = false;
        button.disabled = false;
        button.textContent = original;
      });
  });
}
