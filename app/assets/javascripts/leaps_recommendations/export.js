(function () {
  function timestamp() {
    var d = new Date();
    function p(n) { return String(n).padStart(2, '0'); }
    return '' + d.getFullYear() + p(d.getMonth() + 1) + p(d.getDate()) + '_' + p(d.getHours()) + p(d.getMinutes());
  }

  var exporting = false;

  function exportPng(root, fname) {
    var bg = getComputedStyle(document.body).backgroundColor || '#ffffff';

    // 匯出前把所有 overflow:auto/scroll 容器暫時改為 visible，匯出後還原。
    // 必須無條件處理，不能只看 live DOM 有沒有實際溢出：html-to-image 的
    // clone 在 SVG foreignObject 內字體度量略有差異，live 無溢出的容器在
    // clone 裡可能溢出幾 px，就會把捲軸畫進輸出、蓋住最後一列（實測 NVTS）。
    var expanded = [];
    root.querySelectorAll('*').forEach(function (el) {
      var cs = getComputedStyle(el);
      if (/(auto|scroll)/.test(cs.overflow + cs.overflowX + cs.overflowY)) {
        expanded.push({ el: el, style: el.getAttribute('style') });
        el.style.overflow = 'visible';
        if (el.scrollHeight > el.clientHeight + 1) {
          el.style.maxHeight = 'none';
          el.style.height = 'auto';
        }
      }
    });
    // data-export-exclude 元素（字卡區等）暫時 display:none：html-to-image 的
    // filter 只是不畫內容，root 的量測高度仍會把它們算進去，展開中的字卡會在
    // 輸出底部留下一大段空白（實測 +2200px）。隱藏後畫布高度即為純資料內容。
    root.querySelectorAll('[data-export-exclude]').forEach(function (el) {
      expanded.push({ el: el, style: el.getAttribute('style') });
      el.style.display = 'none';
    });
    function restoreExpanded() {
      expanded.forEach(function (s) {
        if (s.style === null) s.el.removeAttribute('style');
        else s.el.setAttribute('style', s.style);
      });
    }

    return htmlToImage.toPng(root, {
      pixelRatio: 2,
      backgroundColor: bg,
      filter: function (node) {
        return !(node.nodeType === 1 && node.hasAttribute && node.hasAttribute('data-export-exclude'));
      }
    }).then(function (dataUrl) {
      var a = document.createElement('a');
      a.href = dataUrl;
      a.download = fname + '.png';
      document.body.appendChild(a);
      a.click();
      a.remove();
    }).finally(restoreExpanded);
  }

  document.addEventListener('click', function (e) {
    var btnEl = e.target.closest('[data-leaps-export]');
    if (!btnEl || btnEl.disabled || exporting) return;

    var kind = btnEl.getAttribute('data-leaps-export');
    if (kind === 'png' && typeof htmlToImage === 'undefined') { alert('匯出元件未載入，請重新整理頁面'); return; }
    if (kind === 'pdf' && typeof jspdf === 'undefined') { alert('PDF 元件未載入，請重新整理頁面'); return; }

    var root = document.getElementById('leaps-export-root');
    if (!root) return;

    var pngBtn = document.getElementById('leaps-export-png');
    var pdfBtn = document.getElementById('leaps-export-pdf');
    var origText = btnEl.textContent;
    exporting = true;
    [pngBtn, pdfBtn].forEach(function (b) { if (b) b.disabled = true; });
    btnEl.textContent = '匯出中…';

    var symEl  = document.getElementById('leaps-symbol-input');
    var symbol = (symEl && symEl.value ? symEl.value : 'UNKNOWN').toUpperCase();
    var fname  = 'leaps_' + symbol + '_' + timestamp();

    // Phase J：PNG 走既有 DOM 截圖路線（完全不動）；PDF 改走向量文字
    // 路線，直接從結構化資料繪製，不需要 DOM 截圖或 overflow/exclude 處理。
    var task = kind === 'png' ? exportPng(root, fname) : window.__leapsExportVectorPdf(fname);

    task.catch(function (err) {
      alert('匯出失敗：' + (err && err.message ? err.message : err));
    }).finally(function () {
      exporting = false;
      [pngBtn, pdfBtn].forEach(function (b) { if (b) b.disabled = false; });
      btnEl.textContent = origText;
    });
  });
})();
