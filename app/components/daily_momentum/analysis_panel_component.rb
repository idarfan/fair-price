# frozen_string_literal: true

class DailyMomentum::AnalysisPanelComponent < ApplicationComponent
  def view_template
    div(id: "analysis-panel", class: "bg-white rounded-xl border border-gray-100 shadow-sm overflow-hidden") do
      render_header
      render_placeholder
      render_tab_bar
      render_tab_contents
    end
    render_script
  end

  private

  def render_header
    div(class: "px-5 py-4 border-b border-gray-100 flex items-center justify-between") do
      h2(class: "font-semibold text-gray-900") do
        span(class: "mr-2") { plain("🐱") }
        plain("歐歐投資分析")
      end
      span(class: "text-xs text-indigo-400 font-medium") { plain("Powered by Groq / Llama 3.3") }
    end
  end

  def render_placeholder
    div(id: "analysis-placeholder", class: "px-5 py-10 text-center text-sm text-gray-400") do
      span(class: "block text-2xl mb-2") { plain("🐾") }
      plain("點擊觀察名單中的 🐱 按鈕，獲取個股 AI 投資分析")
    end
  end

  def render_tab_bar
    div(
      id:    "analysis-tab-bar",
      class: "hidden bg-gray-50 border-b border-gray-100 px-4 py-2 flex items-center gap-1 flex-wrap"
    )
  end

  def render_tab_contents
    div(id: "analysis-tab-contents", class: "px-5 py-4")
  end

  def render_script # rubocop:disable Metrics/MethodLength
    script do
      raw <<~'JS'.html_safe
        (function () {
          var loaded    = {};
          var streaming = {};

          // ── 🐱 button click ───────────────────────────────────────────
          document.addEventListener('click', function (e) {
            var btn = e.target.closest('[data-start-analysis]');
            if (!btn) return;
            startAnalysis(btn.dataset.startAnalysis);
          });

          function startAnalysis(symbol) {
            if (!document.getElementById('atab-' + symbol)) createTab(symbol);
            activateTab(symbol);
            if (!loaded[symbol] && !streaming[symbol]) streamAnalysis(symbol);
          }

          // ── Tab management ────────────────────────────────────────────
          function createTab(symbol) {
            var bar      = document.getElementById('analysis-tab-bar');
            var contents = document.getElementById('analysis-tab-contents');
            document.getElementById('analysis-placeholder').classList.add('hidden');
            bar.classList.remove('hidden');

            var tab = document.createElement('button');
            tab.type      = 'button';
            tab.id        = 'atab-' + symbol;
            tab.className = 'atab px-3 py-1.5 text-xs font-mono font-semibold rounded-md border border-transparent transition-colors text-gray-500 hover:text-indigo-600';
            tab.textContent = symbol;
            tab.addEventListener('click', function () { activateTab(symbol); });
            bar.appendChild(tab);

            var panel = document.createElement('div');
            panel.id        = 'apanel-' + symbol;
            panel.className = 'apanel hidden';

            var chartDiv = document.createElement('div');
            chartDiv.id = 'apanel-chart-' + symbol;
            chartDiv.className = 'mb-4';
            panel.appendChild(chartDiv);

            var textDiv = document.createElement('div');
            textDiv.id = 'apanel-text-' + symbol;
            panel.appendChild(textDiv);

            contents.appendChild(panel);

            if (typeof window.mountTechChart === 'function') {
              window.mountTechChart(chartDiv, symbol);
            }
          }

          function activateTab(symbol) {
            document.querySelectorAll('.atab').forEach(function (t) {
              t.classList.remove('bg-white', 'shadow-sm', 'text-indigo-700', 'border-indigo-200');
              t.classList.add('text-gray-500');
            });
            var tab = document.getElementById('atab-' + symbol);
            if (tab) {
              tab.classList.add('bg-white', 'shadow-sm', 'text-indigo-700', 'border-indigo-200');
              tab.classList.remove('text-gray-500');
            }
            document.querySelectorAll('.apanel').forEach(function (p) { p.classList.add('hidden'); });
            var panel = document.getElementById('apanel-' + symbol);
            if (panel) panel.classList.remove('hidden');

            document.getElementById('analysis-panel').scrollIntoView({ behavior: 'smooth', block: 'nearest' });
          }

          // ── SSE streaming ─────────────────────────────────────────────
          function streamAnalysis(symbol) {
            streaming[symbol] = true;
            var textDiv = document.getElementById('apanel-text-' + symbol);
            var buffer = '';

            var pre = document.createElement('pre');
            pre.className = 'whitespace-pre-wrap text-sm text-gray-800 leading-relaxed font-sans';
            pre.textContent = '歐歐思考中... 🐾';
            textDiv.innerHTML = '';
            textDiv.appendChild(pre);

            if (typeof NProgress !== 'undefined') { NProgress.start(); NProgress.set(0.2); }

            var source = new EventSource(
              '/momentum/analysis?symbol=' + encodeURIComponent(symbol)
            );

            source.onmessage = function (e) {
              if (e.data === '[DONE]') {
                source.close();
                loaded[symbol]    = true;
                streaming[symbol] = false;
                if (typeof NProgress !== 'undefined') NProgress.done();
                renderMarkdown(symbol, buffer);
                return;
              }
              try {
                buffer += JSON.parse(e.data);
                pre.textContent = buffer;
                if (typeof NProgress !== 'undefined' && buffer.length < 200) NProgress.set(0.5);
              } catch (_) {}
            };

            source.onerror = function () {
              source.close();
              streaming[symbol] = false;
              loaded[symbol]    = false;
              if (typeof NProgress !== 'undefined') NProgress.done();
              textDiv.innerHTML =
                '<div class="py-6 text-center">' +
                  '<p class="text-red-400 text-sm mb-3">串流中斷，請重試</p>' +
                  '<button type="button" data-retry-analysis="' + symbol + '" ' +
                    'class="px-4 py-1.5 text-xs font-medium bg-indigo-50 text-indigo-600 ' +
                    'rounded-full border border-indigo-200 hover:bg-indigo-100 transition-colors">' +
                    '🔄 重新分析' +
                  '</button>' +
                '</div>';
            };
          }

          // ── Markdown rendering (after stream completes) ───────────────
          function renderMarkdown(symbol, text) {
            var textDiv = document.getElementById('apanel-text-' + symbol);
            if (!textDiv) return;

            var csrf = document.querySelector('meta[name="csrf-token"]');
            fetch('/momentum/render_markdown', {
              method: 'POST',
              headers: {
                'Content-Type': 'application/json',
                'X-CSRF-Token': csrf ? csrf.getAttribute('content') : ''
              },
              body: JSON.stringify({ text: text })
            })
              .then(function (r) { return r.json(); })
              .then(function (data) {
                textDiv.innerHTML =
                  '<div id="apanel-body-' + symbol + '" class="md-body text-sm text-gray-800 leading-relaxed overflow-x-auto">' + data.html + '</div>' +
                  '<div class="flex items-center gap-2 mt-4 pt-3 border-t border-gray-100">' +
                    '<button type="button" data-export-png="' + symbol + '" ' +
                      'class="inline-flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium rounded-md bg-gray-100 hover:bg-gray-200 text-gray-600 transition-colors">' +
                      '⬇ 下載 PNG' +
                    '</button>' +
                    '<button type="button" data-export-pdf="' + symbol + '" ' +
                      'class="inline-flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium rounded-md bg-gray-100 hover:bg-gray-200 text-gray-600 transition-colors">' +
                      '⬇ 下載 PDF' +
                    '</button>' +
                  '</div>';
              })
              .catch(function () {
                textDiv.innerHTML =
                  '<pre class="whitespace-pre-wrap text-sm text-gray-800 leading-relaxed font-sans">' + text + '</pre>';
              });
          }

          // ── Retry / Export handlers ────────────────────────────────────
          document.addEventListener('click', function (e) {
            var retryBtn = e.target.closest('[data-retry-analysis]');
            if (retryBtn) { startAnalysis(retryBtn.dataset.retryAnalysis); return; }
            var pngBtn = e.target.closest('[data-export-png]');
            if (pngBtn) { exportPng(pngBtn.dataset.exportPng); return; }
            var pdfBtn = e.target.closest('[data-export-pdf]');
            if (pdfBtn) { exportPdf(pdfBtn.dataset.exportPdf); return; }
          });

          function exportPng(symbol) {
            var body = document.getElementById('apanel-body-' + symbol);
            if (!body || typeof htmlToImage === 'undefined') return;

            htmlToImage.toPng(body, { pixelRatio: 2, backgroundColor: '#ffffff' })
              .then(function (dataUrl) {
                var link = document.createElement('a');
                link.download = symbol + '_歐歐分析_' + new Date().toISOString().slice(0, 10) + '.png';
                link.href = dataUrl;
                document.body.appendChild(link);
                link.click();
                document.body.removeChild(link);
              });
          }

          function exportPdf(symbol) {
            var body = document.getElementById('apanel-body-' + symbol);
            if (!body) return;

            // Use hidden iframe so print dialog does not freeze the main window.
            var iframe = document.createElement('iframe');
            iframe.style.cssText = 'position:fixed;top:-9999px;left:-9999px;width:900px;height:600px;border:none';
            document.body.appendChild(iframe);

            var html =
              '<!DOCTYPE html><html lang="zh-TW"><head>' +
              '<meta charset="utf-8">' +
              '<title>' + symbol + ' 歐歐投資分析</title>' +
              '<style>' +
                'body{font-family:sans-serif;font-size:13px;color:#111827;padding:2rem;max-width:780px;margin:0 auto}' +
                'h1{font-size:1.375rem;font-weight:700;color:#111827;margin-top:1.5rem;margin-bottom:.5rem}' +
                'h2{font-size:1.125rem;font-weight:700;color:#111827;margin-top:1.5rem;margin-bottom:.5rem;padding-bottom:.25rem;border-bottom:1px solid #e5e7eb}' +
                'h3{font-size:1rem;font-weight:700;color:#1f2937;margin-top:1.25rem;margin-bottom:.375rem}' +
                'h4{font-size:.9375rem;font-weight:600;color:#374151;margin-top:1rem;margin-bottom:.25rem}' +
                'p{margin-top:.5rem;line-height:1.7}' +
                'ul,ol{margin:.5rem 0 .5rem 1.5rem}li{margin-bottom:.3rem;list-style:disc;line-height:1.65}' +
                'strong{font-weight:600}em{font-style:italic}' +
                'hr{border:none;border-top:1px solid #e5e7eb;margin:1.25rem 0}' +
                'blockquote{border-left:3px solid #c7d2fe;background:#eef2ff;padding:.6rem .75rem;color:#374151;margin:.75rem 0;border-radius:0 .375rem .375rem 0}' +
                'code{background:#f3f4f6;border-radius:.25rem;padding:.1rem .3rem;font-size:.8125rem;font-family:monospace}' +
                'table{width:100%;border-collapse:collapse;margin:.75rem 0;font-size:.8125rem}' +
                'th{background:#f3f4f6;text-align:left;padding:.5rem .75rem;font-weight:600;border:1px solid #d1d5db}' +
                'td{padding:.45rem .75rem;border:1px solid #d1d5db;vertical-align:top}' +
                'tr:nth-child(even) td{background:#f9fafb}' +
                '@media print{body{padding:0}}' +
              '</style>' +
              '</head><body>' +
              '<h2 style="font-size:1.2rem;margin-bottom:1.25rem">🐱 ' + symbol + ' 歐歐投資分析</h2>' +
              body.innerHTML +
              '</body></html>';

            iframe.contentWindow.document.open();
            iframe.contentWindow.document.write(html);
            iframe.contentWindow.document.close();

            setTimeout(function () {
              iframe.contentWindow.focus();
              iframe.contentWindow.print();
              setTimeout(function () { document.body.removeChild(iframe); }, 1000);
            }, 400);
          }
        })();
      JS
    end
  end
end
