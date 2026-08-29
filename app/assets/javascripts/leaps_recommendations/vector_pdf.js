(function () {
  var FONT_ALIAS     = 'NotoSansTC';
  var FONT_FILE      = 'NotoSansTC-Regular.ttf';
  var IPA_FONT_ALIAS = 'NotoSansIPA';
  var IPA_FONT_FILE  = 'NotoSans-Regular-ipa.ttf';

  // 通用字型載入：fetch → arrayBuffer → base64 → addFileToVFS/addFont，
  // 驗證 addFont 真的生效才算成功。任一字型失敗都必須中止匯出，不得
  // fallback 到 jsPDF 內建字型（豆腐字）——這條規則對主字型與 IPA
  // 字型一視同仁，IPA 字型是術語字卡音標顯示的必要條件，不是可選項。
  function loadFontFile(pdf, fontUrl, fontFile, fontAlias, label) {
    if (!fontUrl) return Promise.reject(new Error(label + '字型路徑未提供，無法產生向量 PDF'));
    return fetch(fontUrl).then(function (resp) {
      if (!resp.ok) throw new Error(label + '字型下載失敗（HTTP ' + resp.status + '），已中止匯出');
      return resp.arrayBuffer();
    }).then(function (buf) {
      var bytes = new Uint8Array(buf);
      var binary = '';
      var chunk = 0x8000;
      for (var i = 0; i < bytes.length; i += chunk) {
        binary += String.fromCharCode.apply(null, bytes.subarray(i, i + chunk));
      }
      var base64 = btoa(binary);
      pdf.addFileToVFS(fontFile, base64);
      pdf.addFont(fontFile, fontAlias, 'normal');
      var list = pdf.getFontList();
      if (!list[fontAlias] || list[fontAlias].indexOf('normal') === -1) {
        throw new Error(label + '字型載入失敗（addFont 未生效），已中止匯出');
      }
    });
  }

  function loadFont(pdf, fontUrl, ipaFontUrl) {
    return loadFontFile(pdf, fontUrl, FONT_FILE, FONT_ALIAS, '主')
      .then(function () { return loadFontFile(pdf, ipaFontUrl, IPA_FONT_FILE, IPA_FONT_ALIAS, 'IPA 音標'); })
      .then(function () { pdf.setFont(FONT_ALIAS, 'normal'); });
  }

  // CJK 沒有空白字元，jsPDF 內建 splitTextToSize 依空白斷詞會讓整段中文
  // 衝出頁面右緣不換行——改用逐字寬度量測（getTextWidth）自行換行。
  function wrapCjk(pdf, text, maxWidth) {
    var lines = [];
    var current = '';
    for (var i = 0; i < text.length; i++) {
      var ch = text[i];
      var test = current + ch;
      if (current.length > 0 && pdf.getTextWidth(test) > maxWidth) {
        lines.push(current);
        current = ch;
      } else {
        current = test;
      }
    }
    if (current.length > 0) lines.push(current);
    return lines;
  }

  function hexToRgb(hex) {
    var h = hex.replace('#', '');
    return [parseInt(h.substr(0, 2), 16), parseInt(h.substr(2, 2), 16), parseInt(h.substr(4, 2), 16)];
  }

  function pageBottom(pdf) { return pdf.internal.pageSize.getHeight() - 16; }

  function renderRecoGroup(pdf, group, margin, y, maxWidth) {
    if (!group) return y;
    var bottom = pageBottom(pdf);
    if (y > bottom) { pdf.addPage(); y = margin; bottom = pageBottom(pdf); }
    pdf.setFontSize(11);
    pdf.text(group.label, margin, y);
    y += 6.5;
    if (group.badge) {
      // 彩色徽章比照 HTML render_pick_badge（色塊背景+邊框+圓點+文字），
      // 用同一組 PDF_SIGNAL_HEX（跟排行表流動性欄位、Flow 方向欄同一色票）
      var b = group.badge;
      pdf.setFontSize(8.5);
      var badgeText = b.text + '   ' + b.delta_text;
      var textW = pdf.getTextWidth(badgeText);
      var padX = 3, boxH = 6.5, boxW = textW + padX * 2 + 4;
      pdf.setFillColor.apply(pdf, hexToRgb(b.color.bg));
      pdf.setDrawColor.apply(pdf, hexToRgb(b.color.border));
      pdf.roundedRect(margin, y - boxH + 1.8, boxW, boxH, 1, 1, 'FD');
      pdf.setFillColor.apply(pdf, hexToRgb(b.color.dot));
      pdf.circle(margin + padX + 1, y - boxH / 2 + 1.8, 1, 'F');
      pdf.setTextColor.apply(pdf, hexToRgb(b.color.text));
      pdf.text(badgeText, margin + padX + 4, y);
      pdf.setTextColor(0, 0, 0);
      y += 6;
    }
    pdf.setFontSize(8.5);
    var text = group.no_candidates ? '此天期區間目前沒有符合條件的候選。' : (group.reason || '');
    var paragraphs = text.split('\\n');
    for (var pi = 0; pi < paragraphs.length; pi++) {
      var lines = wrapCjk(pdf, paragraphs[pi], maxWidth);
      for (var li = 0; li < lines.length; li++) {
        if (y > bottom) { pdf.addPage(); y = margin; bottom = pageBottom(pdf); }
        pdf.text(lines[li], margin, y);
        y += 4;
      }
    }
    y += 3;
    return y;
  }

  // 卡片底色/邊框比照 HTML 版 leaps-concept-card／leaps-vocab-card
  // （奇數綠底 #dcfce7、偶數紫底 #ede9fe、橘框 #f97316，見 application.css）。
  var CARD_FILL_COLORS = ['#dcfce7', '#ede9fe'];
  var CARD_BORDER_COLOR = '#f97316';
  var CARD_TITLE_COLOR = '#111827';
  var CARD_BODY_COLOR = '#1f2937';

  // 量測卡片段落換行後的總高度，用來在畫底色框之前先算好框的高度。
  function measureWrappedLines(pdf, paragraphs, maxWidth) {
    var wrapped = [];
    var total = 0;
    for (var pi = 0; pi < paragraphs.length; pi++) {
      var lines = wrapCjk(pdf, paragraphs[pi], maxWidth);
      wrapped.push(lines);
      total += lines.length;
    }
    return { wrapped: wrapped, lineCount: total };
  }

  function renderConceptCards(pdf, cards, margin, y, maxWidth) {
    if (!cards || !cards.length) return y;
    var bottom = pageBottom(pdf);
    if (y > bottom) { pdf.addPage(); y = margin; bottom = pageBottom(pdf); }
    pdf.setFontSize(9);
    pdf.setTextColor(107, 114, 128);
    pdf.text('名詞解釋（以本次推薦合約的實際數值試算）', margin, y);
    pdf.setTextColor(0, 0, 0);
    y += 6;
    for (var ci = 0; ci < cards.length; ci++) {
      var card = cards[ci];
      pdf.setFontSize(8.5);
      var measured = measureWrappedLines(pdf, card.paragraphs, maxWidth - 6);
      var titleH = 5, lineH = 4;
      var cardH = titleH + measured.lineCount * lineH + 3;
      if (y - 4 + 5 + cardH + 3 > bottom) { pdf.addPage(); y = margin; bottom = pageBottom(pdf); }

      var innerX = margin + 3;
      var textY = y + 5;
      pdf.setFillColor.apply(pdf, hexToRgb(CARD_FILL_COLORS[ci % 2]));
      pdf.setDrawColor.apply(pdf, hexToRgb(CARD_BORDER_COLOR));
      pdf.setLineWidth(0.35);
      pdf.roundedRect(margin, y - 4, maxWidth, 5 + titleH + measured.lineCount * lineH + 3, 2, 2, 'FD');

      pdf.setFontSize(10.5);
      pdf.setTextColor.apply(pdf, hexToRgb(CARD_TITLE_COLOR));
      pdf.text(card.title, innerX, textY);
      textY += titleH;
      pdf.setFontSize(8.5);
      pdf.setTextColor.apply(pdf, hexToRgb(CARD_BODY_COLOR));
      for (var pi = 0; pi < measured.wrapped.length; pi++) {
        var lines = measured.wrapped[pi];
        for (var li = 0; li < lines.length; li++) {
          pdf.text(lines[li], innerX, textY);
          textY += lineH;
        }
      }
      pdf.setTextColor(0, 0, 0);
      y = textY + 4;
    }
    y += 2;
    return y;
  }

  function renderVocabCards(pdf, cards, margin, y, maxWidth) {
    if (!cards || !cards.length) return y;
    var bottom = pageBottom(pdf);
    if (y > bottom) { pdf.addPage(); y = margin; bottom = pageBottom(pdf); }
    pdf.setFontSize(13);
    pdf.text('術語字卡', margin, y);
    y += 4;
    pdf.setFontSize(8);
    pdf.setTextColor(156, 163, 175);
    pdf.text('（正反面內容攤平合併顯示）', margin, y);
    pdf.setTextColor(0, 0, 0);
    y += 6;
    var innerWidth = maxWidth - 6;
    for (var vi = 0; vi < cards.length; vi++) {
      var card = cards[vi];
      pdf.setFontSize(7.5);
      var hintLines = wrapCjk(pdf, card.hint, innerWidth);
      pdf.setFontSize(8);
      var backLines = wrapCjk(pdf, card.back, innerWidth);
      pdf.setFontSize(7.5);
      var exLines = wrapCjk(pdf, card.ex, innerWidth);
      var cardH = 4.2 + hintLines.length * 3.6 + backLines.length * 3.8 + exLines.length * 3.6 + 3;
      // 卡片可能整張跨頁面過長，這裡只確保「至少一行」不被切在頁尾。
      if (y - 4 + 5 + cardH > bottom && cardH <= bottom - margin) {
        pdf.addPage(); y = margin; bottom = pageBottom(pdf);
      } else if (y > bottom - 10) {
        pdf.addPage(); y = margin; bottom = pageBottom(pdf);
      }

      var innerX = margin + 3;
      pdf.setFillColor.apply(pdf, hexToRgb(CARD_FILL_COLORS[vi % 2]));
      pdf.setDrawColor.apply(pdf, hexToRgb(CARD_BORDER_COLOR));
      pdf.setLineWidth(0.35);
      pdf.roundedRect(margin, y - 4, maxWidth, 5 + cardH, 2, 2, 'FD');

      // 混合字型繪製同一行：英文/中文用嵌入的 Noto Sans TC 子集，
      // 音標用第二個嵌入字型 NotoSansIPA（Noto Sans 拉丁字型子集，
      // 涵蓋 Noto Sans TC 缺少的 ɪ/ɛ/ə/ʊ/ˈ/ː 等 IPA Extensions 符號）。
      // jsPDF 單次 pdf.text() 呼叫只能用單一字型，混合字型需要逐段
      // 呼叫 getTextWidth() 手動定位 x 座標分段畫。
      pdf.setFontSize(10);
      var vx = innerX;
      pdf.setFont(FONT_ALIAS, 'normal');
      pdf.setTextColor.apply(pdf, hexToRgb(CARD_TITLE_COLOR));
      var enSeg = card.en + '  ';
      pdf.text(enSeg, vx, y);
      vx += pdf.getTextWidth(enSeg);

      pdf.setFont(IPA_FONT_ALIAS, 'normal');
      var ipaSeg = card.ipa + '  ';
      pdf.text(ipaSeg, vx, y);
      vx += pdf.getTextWidth(ipaSeg);

      pdf.setFont(FONT_ALIAS, 'normal');
      pdf.text('— ' + card.zh, vx, y);
      y += 4.2;
      pdf.setFontSize(7.5);
      pdf.setTextColor(107, 114, 128);
      for (var hi = 0; hi < hintLines.length; hi++) {
        pdf.text(hintLines[hi], innerX, y);
        y += 3.6;
      }
      pdf.setTextColor.apply(pdf, hexToRgb(CARD_BODY_COLOR));
      pdf.setFontSize(8);
      for (var bi = 0; bi < backLines.length; bi++) {
        pdf.text(backLines[bi], innerX, y);
        y += 3.8;
      }
      pdf.setTextColor(107, 114, 128);
      pdf.setFontSize(7.5);
      for (var ei = 0; ei < exLines.length; ei++) {
        pdf.text(exLines[ei], innerX, y);
        y += 3.6;
      }
      pdf.setTextColor(0, 0, 0);
      y += 3 + 4;
    }
    return y;
  }

  function renderCandidatesTable(pdf, rows, margin, y) {
    var head = [['到期日','DTE','履約價','Delta','OI','Volume','流動性判斷','Bid','Ask','Mid',
                 'Spread%','內在價值','外在價值','外在佔比','Time Value%','IV','Vega','被指派機率']];
    var body = rows.map(function (r) {
      return [r.expiration_date, r.dte, r.strike, r.delta, r.oi, r.volume, r.liquidity,
              r.bid, r.ask, r.mid, r.spread, r.intrinsic, r.extrinsic, r.extrinsic_pct,
              r.time_value_pct, r.iv, r.vega, r.itm_prob];
    });
    var liqCol = 6;
    pdf.autoTable({
      head: head, body: body, startY: y,
      margin: { left: margin, right: margin },
      styles: { font: FONT_ALIAS, fontSize: 6.5, cellPadding: 1.2, textColor: [55, 65, 81] },
      headStyles: { font: FONT_ALIAS, fillColor: [243, 244, 246], textColor: [55, 65, 81], fontSize: 6.5 },
      didParseCell: function (hd) {
        if (hd.section === 'body' && hd.column.index === liqCol) {
          var rgb = rows[hd.row.index].liquidity_rgb;
          if (rgb) {
            hd.cell.styles.fillColor = hexToRgb(rgb.bg);
            hd.cell.styles.textColor = hexToRgb(rgb.text);
          }
        }
      }
    });
    return pdf.lastAutoTable.finalY + 8;
  }

  function renderFlowTable(pdf, rows, margin, y, summary, highlights, maxWidth) {
    var bottom = pageBottom(pdf);
    if (y > bottom) { pdf.addPage(); y = margin; bottom = pageBottom(pdf); }
    pdf.setFontSize(11);
    pdf.text('Options Flow — 情緒參考，非排序依據', margin, y);
    if (summary) {
      // 右上角 Call/Put 總額（比照 HTML 頁面右上角同一塊資訊，Call 綠字／Put 紅字）
      pdf.setFontSize(9);
      var callText = 'Call ' + summary.call_total;
      var sep = '  ·  ';
      var putText = 'Put ' + summary.put_total;
      var totalWidth = pdf.getTextWidth(callText) + pdf.getTextWidth(sep) + pdf.getTextWidth(putText);
      var sx = margin + maxWidth - totalWidth;
      pdf.setTextColor.apply(pdf, hexToRgb(summary.call_color));
      pdf.text(callText, sx, y);
      sx += pdf.getTextWidth(callText);
      pdf.setTextColor(156, 163, 175);
      pdf.text(sep, sx, y);
      sx += pdf.getTextWidth(sep);
      pdf.setTextColor.apply(pdf, hexToRgb(summary.put_color));
      pdf.text(putText, sx, y);
      pdf.setTextColor(0, 0, 0);
    }
    y += 4.5;
    if (summary && summary.date) {
      pdf.setFontSize(8);
      pdf.setTextColor(107, 114, 128);
      pdf.text(summary.date + ' · 前 20 大成交（依 Premium 降序）', margin, y);
      pdf.setTextColor(0, 0, 0);
      y += 5;
    }
    if (highlights && highlights.length) {
      pdf.setFontSize(8.5);
      pdf.setTextColor(29, 78, 216);
      pdf.text('排行候選 × 今日 Flow 重疊', margin, y);
      y += 4;
      pdf.setFontSize(7.5);
      for (var hi = 0; hi < highlights.length; hi++) {
        if (y > bottom) { pdf.addPage(); y = margin; bottom = pageBottom(pdf); }
        var lines = wrapCjk(pdf, highlights[hi], maxWidth);
        for (var hli = 0; hli < lines.length; hli++) {
          pdf.text(lines[hli], margin, y);
          y += 3.6;
        }
      }
      pdf.setTextColor(0, 0, 0);
      y += 2;
    }
    var head = [['類型','履約價','到期日','DTE','Delta','Code','Size','Side','Premium','方向']];
    var body = rows.map(function (t) {
      return [t.type, t.strike, t.expires, t.dte, t.delta, t.code, t.size, t.side, t.premium, t.direction];
    });
    var dirCol = 9;
    pdf.autoTable({
      head: head, body: body, startY: y,
      margin: { left: margin, right: margin },
      styles: { font: FONT_ALIAS, fontSize: 7, cellPadding: 1.2 },
      headStyles: { font: FONT_ALIAS, fillColor: [243, 244, 246], textColor: [55, 65, 81], fontSize: 7 },
      didParseCell: function (hd) {
        if (hd.section === 'body' && hd.column.index === dirCol) {
          var rgb = rows[hd.row.index].direction_rgb;
          if (rgb) hd.cell.styles.textColor = hexToRgb(rgb.text);
        }
      }
    });
    return pdf.lastAutoTable.finalY + 8;
  }

  function buildVectorPdf(pdf, data) {
    var pageW = pdf.internal.pageSize.getWidth();
    var pageH = pdf.internal.pageSize.getHeight();
    var margin = 12;
    var y = margin;

    pdf.setFont(FONT_ALIAS, 'normal');
    pdf.setFontSize(16);
    pdf.text('LEAPS Call 候選排行 — ' + data.symbol, margin, y);
    y += 6;
    pdf.setFontSize(9);
    pdf.setTextColor(107, 114, 128);
    pdf.text('Delta ≥ 0.60 深度價內 Call · 依 OI 由高到低排序', margin, y);
    pdf.setTextColor(0, 0, 0);
    y += 8;

    if (data.recommendation) {
      y = renderRecoGroup(pdf, data.recommendation.near_term, margin, y, pageW - margin * 2);
      y = renderRecoGroup(pdf, data.recommendation.far_term, margin, y, pageW - margin * 2);
    }

    if (data.concept_cards && data.concept_cards.length) {
      if (y > pageH - 40) { pdf.addPage(); y = margin; }
      y = renderConceptCards(pdf, data.concept_cards, margin, y, pageW - margin * 2);
    }

    if (data.candidates && data.candidates.length) {
      if (y > pageH - 40) { pdf.addPage(); y = margin; }
      y = renderCandidatesTable(pdf, data.candidates, margin, y);
    }

    if (data.flow_rows && data.flow_rows.length) {
      if (y > pageH - 40) { pdf.addPage(); y = margin; }
      // y 是逐段累加的版面游標。這裡（與下面 vocab cards）是目前的最後一段，
      // 回傳值當下沒人讀，但保留賦值才不會讓之後新增區段的人漏接游標。
      // eslint-disable-next-line no-useless-assignment
      y = renderFlowTable(pdf, data.flow_rows, margin, y, data.flow_summary, data.flow_highlights, pageW - margin * 2);
    }

    if (data.vocab_cards && data.vocab_cards.length) {
      pdf.addPage(); y = margin; // 教學資源另起一頁，跟查詢結果本身分開
      // eslint-disable-next-line no-useless-assignment
      y = renderVocabCards(pdf, data.vocab_cards, margin, y, pageW - margin * 2);
    }

    var pageCount = pdf.internal.getNumberOfPages();
    for (var p = 1; p <= pageCount; p++) {
      pdf.setPage(p);
      pdf.setFont(FONT_ALIAS, 'normal');
      pdf.setFontSize(7);
      pdf.setTextColor(156, 163, 175);
      pdf.text('僅供策略篩選參考，非投資建議，請自行評估。', margin, pageH - 6);
      pdf.setTextColor(0, 0, 0);
    }
  }

  window.__leapsExportVectorPdf = function (fname) {
    var root = document.getElementById('leaps-export-root');
    var fontUrl    = root ? root.getAttribute('data-pdf-font-url') : null;
    var ipaFontUrl = root ? root.getAttribute('data-pdf-ipa-font-url') : null;
    var dataEl = document.getElementById('leaps-pdf-data');

    var payload;
    try {
      payload = JSON.parse(dataEl ? dataEl.textContent : 'null');
    } catch {
      return Promise.reject(new Error('PDF 資料解析失敗，已中止匯出'));
    }
    if (!payload) return Promise.reject(new Error('找不到匯出資料，已中止匯出'));

    var pdf = new jspdf.jsPDF({ orientation: 'landscape', unit: 'mm', format: 'a4' });

    return loadFont(pdf, fontUrl, ipaFontUrl).then(function () {
      buildVectorPdf(pdf, payload);
      pdf.save(fname + '.pdf');
    });
  };
})();
