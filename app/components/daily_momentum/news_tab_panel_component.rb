# frozen_string_literal: true

class DailyMomentum::NewsTabPanelComponent < ApplicationComponent
  def view_template
    div(id: "stock-news-panel", class: "bg-white rounded-xl border border-gray-100 shadow-sm overflow-hidden") do
      render_header
      render_placeholder
      render_tab_bar
      render_tab_contents
    end
    render_script
  end

  private

  def render_header
    div(class: "px-5 py-4 border-b border-gray-100") do
      h2(class: "font-semibold text-gray-900") do
        span(class: "mr-2") { plain("📰") }
        plain("個股新聞")
      end
    end
  end

  def render_placeholder
    div(id: "news-placeholder", class: "px-5 py-10 text-center text-sm text-gray-400") do
      span(class: "block text-2xl mb-2") { plain("👆") }
      plain("點擊觀察名單中的股票代號，查看相關新聞")
    end
  end

  def render_tab_bar
    # Tab bar — hidden until first symbol is clicked
    div(
      id:    "news-tab-bar",
      class: "hidden border-b border-gray-200 px-4 flex items-center gap-0 flex-wrap"
    )
  end

  def render_tab_contents
    div(id: "news-tab-contents", class: "px-5")
  end

  def render_script # rubocop:disable Metrics/MethodLength
    script do
      raw <<~JS.html_safe
        (function () {
          var loaded = {};

          // ── Symbol click → load news ──────────────────────────────────
          document.addEventListener('click', function (e) {
            var btn = e.target.closest('[data-fetch-news]');
            if (!btn) return;
            activateOrLoad(btn.dataset.fetchNews);
          });

          function activateOrLoad(symbol) {
            if (loaded[symbol]) { activateTab(symbol); return; }
            createTab(symbol);
            fetchNews(symbol);
          }

          // ── Tab creation ──────────────────────────────────────────────
          function createTab(symbol) {
            var bar      = document.getElementById('news-tab-bar');
            var contents = document.getElementById('news-tab-contents');
            document.getElementById('news-placeholder').classList.add('hidden');
            bar.classList.remove('hidden');

            var initials = symbol.slice(0, 2);
            var tab = document.createElement('button');
            tab.type      = 'button';
            tab.id        = 'ntab-' + symbol;
            tab.className = 'ntab inline-flex items-center gap-1.5 px-4 py-2.5 text-xs font-mono font-semibold border-b-2 border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300 -mb-px transition-colors whitespace-nowrap';
            tab.innerHTML =
              '<span class="relative flex-shrink-0 w-5 h-5">' +
                '<img class="tab-logo w-5 h-5 rounded-full object-contain bg-white border border-gray-100"' +
                     ' src="https://assets.parqet.com/logos/symbol/' + symbol + '?format=jpg"' +
                     ' data-fallback="https://static2.finnhub.io/file/publicdatany/finnhubimage/stock_logo/' + symbol + '.png"' +
                     ' alt="' + symbol + '">' +
                '<span class="tab-logo-fallback absolute inset-0 rounded-full bg-gray-800 text-white text-[8px] font-bold items-center justify-center" style="display:none">' + initials + '</span>' +
              '</span>' +
              '<span>' + symbol + '</span>';
            tab.querySelector('.tab-logo').addEventListener('error', function() {
              var img = this;
              var fb  = img.dataset.fallback;
              if (fb && img.src !== fb) {
                img.src = fb;
              } else {
                img.style.display = 'none';
                img.nextElementSibling.style.display = 'flex';
              }
            });
            tab.addEventListener('click', function () { activateTab(symbol); });
            bar.appendChild(tab);

            var panel = document.createElement('div');
            panel.id        = 'npanel-' + symbol;
            panel.className = 'npanel hidden divide-y divide-gray-100';
            panel.innerHTML = '<div class="py-10 text-center text-gray-400 text-sm">載入中…</div>';
            contents.appendChild(panel);

            activateTab(symbol);
          }

          // ── Tab activation ────────────────────────────────────────────
          function activateTab(symbol) {
            document.querySelectorAll('.ntab').forEach(function (t) {
              t.classList.remove('border-blue-600', 'text-blue-700');
              t.classList.add('border-transparent', 'text-gray-500');
            });
            var tab = document.getElementById('ntab-' + symbol);
            if (tab) {
              tab.classList.remove('border-transparent', 'text-gray-500');
              tab.classList.add('border-blue-600', 'text-blue-700');
            }

            document.querySelectorAll('.npanel').forEach(function (p) { p.classList.add('hidden'); });
            var panel = document.getElementById('npanel-' + symbol);
            if (panel) panel.classList.remove('hidden');

            document.getElementById('stock-news-panel').scrollIntoView({ behavior: 'smooth', block: 'nearest' });
          }

          // ── News fetch ────────────────────────────────────────────────
          function fetchNews(symbol) {
            fetch('/momentum/news?symbol=' + encodeURIComponent(symbol))
              .then(function (r) { return r.json(); })
              .then(function (data) {
                loaded[symbol] = true;
                renderNews(symbol, data.news);
              })
              .catch(function () { renderErr(symbol); });
          }

          // ── Render helpers ────────────────────────────────────────────
          function renderNews(symbol, news) {
            var panel = document.getElementById('npanel-' + symbol);
            if (!panel) return;
            if (!news || !news.length) {
              panel.innerHTML = '<p class="py-8 text-center text-gray-400 text-sm">目前無相關新聞</p>';
              return;
            }
            panel.innerHTML = news.map(function (n) {
              var bodyHtml = '';
              if (n.content_html && n.content_html.trim()) {
                bodyHtml = '<div class="md-body text-sm text-gray-700 leading-relaxed mb-2 overflow-x-auto">' +
                  n.content_html +
                  '</div>';
              }
              return (
                '<div class="py-4">' +
                  '<p class="text-sm font-semibold text-gray-900 leading-snug mb-2">' + esc(n.headline) + '</p>' +
                  bodyHtml +
                  '<div class="flex flex-wrap items-center gap-x-3 gap-y-1 text-xs text-gray-400 mt-2">' +
                    (n.datetime ? '<span>' + esc(n.datetime) + '</span>' : '') +
                    (n.source   ? '<span class="font-medium">' + esc(n.source) + '</span>' : '') +
                    (n.url
                      ? '<a href="' + esc(n.url) + '" target="_blank" rel="noopener noreferrer" ' +
                          'class="text-blue-500 hover:underline truncate max-w-xs">' + esc(n.source || n.url) + ' ↗</a>'
                      : '') +
                  '</div>' +
                '</div>'
              );
            }).join('');
          }

          function renderErr(symbol) {
            var panel = document.getElementById('npanel-' + symbol);
            if (panel) panel.innerHTML = '<p class="py-8 text-center text-red-400 text-sm">新聞載入失敗，請稍後再試</p>';
          }

          function esc(s) {
            return String(s)
              .replace(/&/g, '&amp;')
              .replace(/</g, '&lt;')
              .replace(/>/g, '&gt;')
              .replace(/"/g, '&quot;');
          }
        })();
      JS
    end
  end
end
