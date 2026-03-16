# frozen_string_literal: true

class Flight::ChatPageComponent < ApplicationComponent
  # @param pairs [Array<Hash>]  [{index:, question:, answer:}, ...]
  def initialize(pairs: [])
    @pairs = pairs
  end

  def view_template
    div(id: "flight-root",
        class: "flex flex-col bg-white rounded-2xl border border-gray-200 shadow-sm overflow-hidden",
        style: "height: calc(100vh - 140px); min-height: 520px") do
      render_header
      div(class: "flex flex-1 overflow-hidden") do
        render_question_panel
        render_vertical_divider
        render_answer_panel
      end
    end
    render_script
  end

  private

  # ── Header ───────────────────────────────────────────────────────────────

  def render_header
    div(class: "flex items-center justify-between px-5 py-3 border-b border-gray-100 bg-gray-50 flex-shrink-0") do
      div(class: "flex items-center gap-3") do
        span(class: "text-2xl") { plain("✈️") }
        div do
          h1(class: "text-base font-bold text-gray-900 leading-tight") { plain("台日航班專家") }
          p(class: "text-xs text-gray-500") { plain("直飛 / 日本國內轉機 / 信用卡策略 / 2026 連假規劃") }
        end
      end
      if @pairs.any?
        a(href: clear_flight_path,
          class: "text-xs text-gray-400 hover:text-red-500 transition-colors px-2 py-1 rounded hover:bg-red-50") do
          plain("清除對話")
        end
      end
    end
  end

  # ── Left: question panel ─────────────────────────────────────────────────

  def render_question_panel
    div(class: "flex flex-col bg-white flex-shrink-0 border-r border-gray-100",
        style: "width: 40%") do
      # section label
      div(class: "px-4 py-2 bg-gray-50 border-b border-gray-100 flex-shrink-0") do
        p(class: "text-xs font-semibold text-gray-400 uppercase tracking-wider") { plain("客戶提問") }
      end

      # scrollable question history
      div(id: "question-list",
          class: "flex-1 overflow-y-auto") do
        if @pairs.empty?
          div(class: "flex flex-col items-center justify-center h-full text-center px-4 py-8 text-gray-300",
              id: "question-empty-hint") do
            span(class: "text-3xl mb-2") { plain("💬") }
            p(class: "text-xs") { plain("還沒有問題，從下方開始提問") }
          end
        else
          @pairs.each do |pair|
            render_question_item(pair)
          end
        end
      end

      # input area (stays at bottom)
      div(class: "border-t border-gray-100 px-4 py-3 flex-shrink-0 space-y-2") do
        textarea(
          id: "flight-input",
          placeholder: "例：四月清明去石垣島，直飛還是轉機比較划算？",
          class: "w-full rounded-xl border border-gray-200 px-3 py-2.5 text-sm text-gray-900 " \
                 "placeholder-gray-400 focus:outline-none focus:ring-2 focus:ring-blue-400 " \
                 "focus:border-transparent resize-none leading-relaxed",
          rows: "3"
        ) { }
        div(class: "flex items-center justify-between") do
          p(class: "text-xs text-gray-400") { plain("Ctrl+Enter 送出") }
          button(
            id: "flight-submit-btn",
            type: "button",
            class: "inline-flex items-center gap-1.5 px-4 py-2 bg-blue-600 hover:bg-blue-700 " \
                   "text-white text-sm font-semibold rounded-xl shadow-sm transition-colors " \
                   "disabled:opacity-50 disabled:cursor-not-allowed"
          ) do
            span(id: "flight-btn-icon") { plain("🔍") }
            span(id: "flight-btn-text") { plain("查詢航班") }
          end
        end
      end
    end
  end

  def render_question_item(pair)
    is_last = pair[:index] == @pairs.length - 1
    div(
      class: "question-item flex items-start gap-2 px-4 py-3 cursor-pointer border-b border-gray-50 " \
             "transition-colors hover:bg-blue-50 #{is_last ? 'bg-blue-50 text-blue-700' : 'text-gray-700'}",
      data: { index: pair[:index] },
      id: "q-item-#{pair[:index]}"
    ) do
      span(class: "text-base flex-shrink-0 mt-0.5") { plain("❓") }
      div(class: "flex-1 min-w-0") do
        p(class: "text-xs leading-relaxed line-clamp-3 #{is_last ? 'font-medium text-blue-800' : ''}") do
          plain(pair[:question].to_s)
        end
      end
    end
  end

  # ── Vertical divider ─────────────────────────────────────────────────────

  def render_vertical_divider
    div(class: "w-1 flex-shrink-0 bg-gradient-to-b from-blue-400 via-indigo-500 to-blue-400")
  end

  # ── Right: answer panel ──────────────────────────────────────────────────

  def render_answer_panel
    div(class: "flex flex-col flex-1 overflow-hidden") do
      div(class: "px-4 py-2 bg-gray-50 border-b border-gray-100 flex items-center justify-between flex-shrink-0") do
        p(class: "text-xs font-semibold text-gray-400 uppercase tracking-wider") { plain("航線專家回覆") }
        span(id: "flight-status",
             class: "hidden text-xs bg-blue-100 text-blue-600 px-2 py-0.5 rounded-full") { plain("查詢中…") }
      end

      div(id: "answer-container", class: "flex-1 overflow-y-auto px-6 py-4") do
        if @pairs.empty?
          render_empty_state
        else
          @pairs.each_with_index do |pair, i|
            render_answer_block(pair, visible: i == @pairs.length - 1)
          end
        end
      end
    end
  end

  def render_answer_block(pair, visible:)
    display = visible ? "" : "display:none"
    div(id: "answer-#{pair[:index]}", class: "flight-answer-block", style: display) do
      if pair[:answer].present?
        div(class: "prose prose-sm max-w-none flight-prose") do
          raw Kramdown::Document.new(pair[:answer], input: "GFM").to_html.html_safe
        end
      else
        div(class: "p-4 bg-yellow-50 border border-yellow-200 rounded-xl text-yellow-700 text-sm") do
          plain("此問題尚未收到回覆")
        end
      end
    end
  end

  def render_empty_state
    div(id: "flight-empty",
        class: "h-full flex flex-col items-center justify-center text-center select-none") do
      span(class: "text-5xl mb-4") { plain("✈️") }
      h2(class: "text-base font-semibold text-gray-500 mb-1") { plain("台日航班專家待命中") }
      p(class: "text-xs text-gray-400 max-w-sm leading-relaxed") do
        plain("從左側輸入旅遊需求，我將分析直飛與日本國內轉機方案，並推薦信用卡策略與 2026 連假注意事項。")
      end
      div(class: "mt-5 flex flex-wrap gap-2 justify-center") do
        [
          "四月去石垣島，有直飛嗎？",
          "台北飛北海道最省錢？",
          "JAL Explorer Pass 怎麼買？",
          "清明連假去沖繩訂票攻略？"
        ].each do |q|
          button(type: "button",
                 class: "example-q px-3 py-1.5 bg-blue-50 hover:bg-blue-100 text-blue-700 " \
                        "text-xs rounded-full transition-colors",
                 data: { question: q }) { plain(q) }
        end
      end
    end
  end

  # ── Script ────────────────────────────────────────────────────────────────

  def render_script
    script do
      raw <<~JS.html_safe
        (function () {
          var input     = document.getElementById('flight-input');
          var btn       = document.getElementById('flight-submit-btn');
          var btnIcon   = document.getElementById('flight-btn-icon');
          var btnText   = document.getElementById('flight-btn-text');
          var container = document.getElementById('answer-container');
          var qList     = document.getElementById('question-list');
          var status    = document.getElementById('flight-status');
          var csrf      = document.querySelector('meta[name="csrf-token"]');
          var currentIndex = #{@pairs.empty? ? -1 : @pairs.length - 1};

          function setLoading(on) {
            btn.disabled        = on;
            btnIcon.textContent = on ? '⏳' : '🔍';
            btnText.textContent = on ? '查詢中…' : '查詢航班';
            status.classList.toggle('hidden', !on);
          }

          function showAnswer(idx) {
            document.querySelectorAll('.flight-answer-block').forEach(function (el) {
              el.style.display = 'none';
            });
            document.querySelectorAll('.question-item').forEach(function (el) {
              var active = parseInt(el.dataset.index) === idx;
              el.classList.toggle('bg-blue-50', active);
              el.classList.toggle('text-blue-700', active);
              el.querySelector('p').classList.toggle('font-medium', active);
              el.querySelector('p').classList.toggle('text-blue-800', active);
            });
            var target = document.getElementById('answer-' + idx);
            if (target) { target.style.display = ''; container.scrollTop = 0; }
            currentIndex = idx;
          }

          // 點擊左側問題項目
          document.addEventListener('click', function (e) {
            var item = e.target.closest('.question-item');
            if (item) { showAnswer(parseInt(item.dataset.index)); return; }

            var exQ = e.target.closest('.example-q');
            if (exQ) { input.value = exQ.dataset.question; input.focus(); submit(); }
          });

          function appendQuestion(idx, text) {
            var hint = document.getElementById('question-empty-hint');
            if (hint) hint.remove();

            var div = document.createElement('div');
            div.id        = 'q-item-' + idx;
            div.className = 'question-item flex items-start gap-2 px-4 py-3 cursor-pointer border-b border-gray-50 transition-colors hover:bg-blue-50 text-gray-700';
            div.dataset.index = idx;
            div.innerHTML =
              '<span class="text-base flex-shrink-0 mt-0.5">❓</span>' +
              '<div class="flex-1 min-w-0"><p class="text-xs leading-relaxed line-clamp-3">' +
              escapeHtml(text) + '</p></div>';
            qList.appendChild(div);
            qList.scrollTop = qList.scrollHeight;
          }

          function appendAnswer(idx, html) {
            var empty = document.getElementById('flight-empty');
            if (empty) empty.remove();

            var div = document.createElement('div');
            div.id        = 'answer-' + idx;
            div.className = 'flight-answer-block';
            div.style.display = 'none';
            div.innerHTML = '<div class="prose prose-sm max-w-none flight-prose">' + html + '</div>';
            container.appendChild(div);
          }

          function escapeHtml(str) {
            return str.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
          }

          function submit() {
            var q = input.value.trim();
            if (!q) { input.focus(); return; }

            setLoading(true);
            input.value = '';

            fetch('/flight/chat', {
              method:  'POST',
              headers: { 'Content-Type': 'application/json',
                         'X-CSRF-Token': csrf ? csrf.content : '' },
              body: JSON.stringify({ message: q })
            })
            .then(function (r) { return r.json(); })
            .then(function (data) {
              setLoading(false);
              if (data.error) {
                var err = document.createElement('div');
                err.className = 'p-4 bg-red-50 border border-red-200 rounded-xl text-red-700 text-sm mb-4';
                err.textContent = data.error;
                container.prepend(err);
              } else {
                appendQuestion(data.index, data.question);
                appendAnswer(data.index, data.reply_html);
                showAnswer(data.index);
              }
            })
            .catch(function () {
              setLoading(false);
              var err = document.createElement('div');
              err.className = 'p-4 bg-red-50 border border-red-200 rounded-xl text-red-700 text-sm mb-4';
              err.textContent = '網路連線失敗，請稍後再試。';
              container.prepend(err);
            });
          }

          btn.addEventListener('click', submit);
          input.addEventListener('keydown', function (e) {
            if (e.key === 'Enter' && (e.ctrlKey || e.metaKey)) { e.preventDefault(); submit(); }
          });
        })();
      JS
    end
    style do
      raw <<~CSS.html_safe
        .line-clamp-3 { display: -webkit-box; -webkit-line-clamp: 3; -webkit-box-orient: vertical; overflow: hidden; }
        @keyframes spin { to { transform: rotate(360deg); } }
        .flight-prose h2 { font-size: 1rem; font-weight: 700; margin: 1.2rem 0 0.4rem; color: #1e3a5f; }
        .flight-prose h3 { font-size: 0.9rem; font-weight: 600; margin: 1rem 0 0.3rem; color: #1e40af; }
        .flight-prose ul, .flight-prose ol { padding-left: 1.4rem; margin: 0.4rem 0 0.8rem; }
        .flight-prose li { margin-bottom: 0.25rem; font-size: 0.875rem; }
        .flight-prose table { width: 100%; border-collapse: collapse; margin: 0.8rem 0; font-size: 0.8rem; }
        .flight-prose th { background: #eff6ff; padding: 0.4rem 0.6rem; text-align: left;
                           border: 1px solid #bfdbfe; color: #1e40af; font-weight: 600; }
        .flight-prose td { padding: 0.35rem 0.6rem; border: 1px solid #e2e8f0; }
        .flight-prose tr:nth-child(even) td { background: #f8fafc; }
        .flight-prose strong { color: #1e3a5f; }
        .flight-prose p { font-size: 0.875rem; margin: 0.4rem 0; line-height: 1.6; }
        .flight-prose blockquote { border-left: 3px solid #93c5fd; padding-left: 0.8rem;
                                   margin: 0.5rem 0; color: #64748b; font-size: 0.85rem; }
        .flight-prose code { background: #f1f5f9; padding: 0.1rem 0.3rem; border-radius: 3px;
                             font-size: 0.8rem; }
        .flight-prose hr { border: none; border-top: 1px solid #e2e8f0; margin: 0.8rem 0; }
      CSS
    end
  end
end
