/**
 * 管理後台：瀏覽軌跡匯出 PDF。
 *
 * 需要的資料由掛載元素的 data attribute 傳入：root.dataset.email
 *
 * 稽核 H-3 Wave 2：原本內嵌在 app/components/admin/users/show_component.rb 的 heredoc 裡。
 * htmlToImage 與 jspdf 由 layout 以獨立 <script> 載入，型別見 types/globals.d.ts。
 */

export function init(root: HTMLElement): void {
  const found = document.getElementById("pageviews-export-pdf-btn");
  if (!(found instanceof HTMLButtonElement)) return;
  // 明確型別的 const：narrowing 在巢狀 function declaration（restore）裡不保證留存。
  const btn: HTMLButtonElement = found;

  function timestamp(): string {
    const d = new Date();
    const p = (n: number): string => String(n).padStart(2, "0");
    return `${d.getFullYear()}${p(d.getMonth() + 1)}${p(d.getDate())}`
      + `_${p(d.getHours())}${p(d.getMinutes())}`;
  }

  btn.addEventListener("click", () => {
    if (btn.disabled) return;
    const panel = document.getElementById("tab-panel-pageviews");
    if (!panel) return;

    const detailsEls = panel.querySelectorAll("details");
    const openStates = Array.from(detailsEls).map((d) => d.open);
    detailsEls.forEach((d) => { d.open = true; });

    const originalText = btn.textContent;
    btn.disabled = true;
    btn.textContent = "匯出中…";

    function restore(): void {
      detailsEls.forEach((d, i) => { d.open = openStates[i] ?? false; });
      btn.disabled = false;
      btn.textContent = originalText;
    }

    const bg = getComputedStyle(document.body).backgroundColor || "#ffffff";
    htmlToImage.toPng(panel, { pixelRatio: 2, backgroundColor: bg })
      .then((dataUrl) => {
        const img = new Image();
        img.onload = (): void => {
          const pdf = new jspdf.jsPDF({
            orientation: "p", unit: "pt", format: "a4", compress: true,
          });
          const pageW = pdf.internal.pageSize.getWidth();
          const pageH = pdf.internal.pageSize.getHeight();
          const imgW = pageW;
          const imgH = img.height * (imgW / img.width);
          let heightLeft = imgH;
          let position = 0;

          pdf.addImage(dataUrl, "PNG", 0, position, imgW, imgH, undefined, "FAST");
          heightLeft -= pageH;
          while (heightLeft > 0) {
            position = heightLeft - imgH;
            pdf.addPage();
            pdf.addImage(dataUrl, "PNG", 0, position, imgW, imgH, undefined, "FAST");
            heightLeft -= pageH;
          }

          // email 取自掛載元素（root），不是被匯出的面板。
          pdf.save(`瀏覽軌跡_${root.dataset["email"] ?? ""}_${timestamp()}.pdf`);
          restore();
        };
        img.onerror = restore;
        img.src = dataUrl;
      })
      .catch(restore);
  });
}
