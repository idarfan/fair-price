/**
 * 管理後台：瀏覽軌跡匯出 PDF。
 *
 * 需要的資料由掛載元素的 data attribute 傳入：root.dataset.email
 *
 * 稽核 H-3 Wave 2：原本內嵌在 app/components/admin/users/show_component.rb 的 heredoc 裡。
 * 原本用 Ruby 插值傳進來的值，改成從掛載元素的 data attribute 讀取。
 * TODO：型別化成 .ts。
 */

export function init(root) {
  (function () {
    var btn = document.getElementById('pageviews-export-pdf-btn');
    if (!btn) return;

    function timestamp() {
      var d = new Date();
      function p(n) { return String(n).padStart(2, '0'); }
      return '' + d.getFullYear() + p(d.getMonth() + 1) + p(d.getDate()) + '_' + p(d.getHours()) + p(d.getMinutes());
    }

    btn.addEventListener('click', function () {
      if (btn.disabled) return;
      var root = document.getElementById('tab-panel-pageviews');
      if (!root) return;

      var detailsEls = root.querySelectorAll('details');
      var openStates = Array.prototype.map.call(detailsEls, function (d) { return d.open; });
      detailsEls.forEach(function (d) { d.open = true; });

      var originalText = btn.textContent;
      btn.disabled = true;
      btn.textContent = '匯出中…';

      function restore() {
        detailsEls.forEach(function (d, i) { d.open = openStates[i]; });
        btn.disabled = false;
        btn.textContent = originalText;
      }

      var bg = getComputedStyle(document.body).backgroundColor || '#ffffff';
      htmlToImage.toPng(root, { pixelRatio: 2, backgroundColor: bg })
        .then(function (dataUrl) {
          var img = new Image();
          img.onload = function () {
            var pdf = new jspdf.jsPDF({ orientation: 'p', unit: 'pt', format: 'a4', compress: true });
            var pageW = pdf.internal.pageSize.getWidth();
            var pageH = pdf.internal.pageSize.getHeight();
            var imgW  = pageW;
            var imgH  = img.height * (imgW / img.width);
            var heightLeft = imgH;
            var position   = 0;

            pdf.addImage(dataUrl, 'PNG', 0, position, imgW, imgH, undefined, 'FAST');
            heightLeft -= pageH;
            while (heightLeft > 0) {
              position = heightLeft - imgH;
              pdf.addPage();
              pdf.addImage(dataUrl, 'PNG', 0, position, imgW, imgH, undefined, 'FAST');
              heightLeft -= pageH;
            }

            pdf.save('瀏覽軌跡_' + (root.dataset.email || '') + '_' + timestamp() + '.pdf');
            restore();
          };
          img.onerror = restore;
          img.src = dataUrl;
        })
        .catch(restore);
    });
  })();
}
