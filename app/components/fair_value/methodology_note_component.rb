# frozen_string_literal: true

class FairValue::MethodologyNoteComponent < ApplicationComponent
  # @param stock_type [String] 股票類型（一般股/金融股/REITs/…）
  # @param stock_type_rationale [String, nil] 為何採用此分類的說明
  # @param valuation_methods [Array<Hash>] 包含 :method, :formula, :rationale 的方法陣列
  # @param growth_rate [Float, nil] 估算成長率
  # @param growth_rate_note [String, nil] 成長率來源說明
  # @param expanded [Boolean] 預設展開或摺疊
  def initialize(
    stock_type:,
    stock_type_rationale: nil,
    valuation_methods: [],
    growth_rate: nil,
    growth_rate_note: nil,
    expanded: false
  )
    @stock_type          = stock_type
    @stock_type_rationale = stock_type_rationale
    @valuation_methods   = valuation_methods
    @growth_rate         = growth_rate
    @growth_rate_note    = growth_rate_note
    @expanded            = expanded
    @uid                 = "methodology-#{rand(10_000)}"
  end

  def view_template
    div(class: "bg-white rounded-xl border border-blue-100 shadow-sm overflow-hidden") do
      # Toggle header
      button(
        type: "button",
        class: "w-full flex items-center justify-between px-5 py-3.5 text-left hover:bg-blue-50 transition-colors",
        data: { toggle: @uid }
      ) do
        div(class: "flex items-center gap-2") do
          span(class: "text-lg") { plain("🔬") }
          span(class: "font-semibold text-blue-800 text-sm") { plain("估值方法論說明") }
          span(class: "text-xs bg-blue-100 text-blue-600 px-2 py-0.5 rounded-full ml-1") { plain(@stock_type) }
        end
        span(id: "#{@uid}-icon", class: "text-blue-400 text-sm") { plain(@expanded ? "▲" : "▼") }
      end

      # Collapsible body
      div(id: @uid, class: "border-t border-blue-100 #{@expanded ? '' : 'hidden'}") do
        div(class: "px-5 py-4 space-y-4") do
          # Stock type rationale
          if @stock_type_rationale
            div(class: "bg-blue-50 rounded-lg p-4") do
              p(class: "text-xs font-semibold text-blue-700 uppercase tracking-wide mb-1") { plain("分類依據") }
              p(class: "text-sm text-blue-800 leading-relaxed") { plain(@stock_type_rationale) }
            end
          end

          # Growth rate source
          if @growth_rate
            div(class: "flex items-start gap-2 text-sm text-gray-600") do
              span(class: "flex-shrink-0 text-base") { plain("📈") }
              div do
                span(class: "font-medium") { plain("預估成長率：") }
                plain(fmt_percent(@growth_rate))
                if @growth_rate_note.present?
                  plain("（來源：#{@growth_rate_note}）")
                end
              end
            end
          end

          # Each method
          if @valuation_methods.any?
            div(class: "space-y-3") do
              p(class: "text-xs font-semibold text-gray-500 uppercase tracking-wide") { plain("各方法說明") }
              @valuation_methods.each_with_index do |m, i|
                div(class: "rounded-lg border border-gray-100 p-3 bg-gray-50") do
                  div(class: "flex items-center gap-2 mb-1.5") do
                    span(class: "font-mono text-xs font-bold bg-blue-600 text-white px-2 py-0.5 rounded") { plain(m[:method]) }
                    span(class: "text-xs text-gray-500") { plain(m[:note]) }
                  end
                  if m[:rationale]
                    p(class: "text-xs text-gray-600 leading-relaxed mb-1.5") { plain(m[:rationale]) }
                  end
                  if m[:formula]
                    p(class: "text-xs font-mono text-indigo-700 bg-indigo-50 rounded px-2 py-1 break-all") { plain(m[:formula]) }
                  end
                end
              end
            end
          end
        end
      end

      toggle_script
    end
  end

  private

  def toggle_script
    script do
      raw <<~JS.html_safe
        (function() {
          var btn = document.querySelector('[data-toggle="#{@uid}"]');
          var panel = document.getElementById('#{@uid}');
          var icon = document.getElementById('#{@uid}-icon');
          if (!btn || !panel) return;
          btn.addEventListener('click', function() {
            var hidden = panel.classList.toggle('hidden');
            icon.textContent = hidden ? '▼' : '▲';
          });
        })();
      JS
    end
  end
end
