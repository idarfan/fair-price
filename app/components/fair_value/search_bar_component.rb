# frozen_string_literal: true

class FairValue::SearchBarComponent < ApplicationComponent
  # @param ticker [String] Pre-filled ticker symbol
  # @param discount_rate [Float] Discount rate as percentage (e.g. 10 = 10%)
  # @param placeholder [String] Input placeholder text
  # @param button_text [String] Submit button label
  # @param show_discount_rate [Boolean] Show the discount rate slider
  # @param compact [Boolean] Render in a compact single-line style
  # @param autofocus [Boolean] Focus the ticker input on load
  def initialize(
    ticker: "",
    discount_rate: 10.0,
    placeholder: "輸入股票代號 (e.g. AAPL, MSFT, TSMC)",
    button_text: "分析",
    show_discount_rate: true,
    compact: false,
    autofocus: false
  )
    @ticker            = ticker.to_s.upcase
    @discount_rate     = discount_rate.to_f
    @placeholder       = placeholder
    @button_text       = button_text
    @show_discount_rate = show_discount_rate
    @compact           = compact
    @autofocus         = autofocus
  end

  def view_template
    div(id: "search-bar-wrapper") do
      if @compact
        compact_form
      else
        full_form
      end
      inline_script
    end
  end

  private

  def full_form
    form(
      id: "ticker-form",
      class: "bg-white rounded-2xl shadow-md p-6 space-y-4"
    ) do
      h2(class: "text-lg font-semibold text-gray-700") { plain("美股公允價值分析") }
      div(class: "flex gap-3") do
        input(
          id: "ticker-input",
          type: "text",
          value: @ticker,
          placeholder: @placeholder,
          class: "flex-1 rounded-lg border border-gray-300 px-4 py-2.5 text-sm uppercase tracking-widest focus:outline-none focus:ring-2 focus:ring-blue-500",
          autocomplete: "off",
          autocapitalize: "characters",
          **(@autofocus ? { autofocus: true } : {})
        )
        button(
          type: "submit",
          class: "bg-blue-600 hover:bg-blue-700 text-white font-medium px-6 py-2.5 rounded-lg text-sm transition-colors"
        ) { plain(@button_text) }
      end
      if @show_discount_rate
        discount_rate_slider
      end
    end
  end

  def compact_form
    form(
      id: "ticker-form",
      class: "flex items-center gap-3 bg-white rounded-xl shadow px-4 py-2"
    ) do
      input(
        id: "ticker-input",
        type: "text",
        value: @ticker,
        placeholder: "代號…",
        class: "w-28 rounded border border-gray-200 px-3 py-1.5 text-sm uppercase tracking-widest focus:outline-none focus:ring-2 focus:ring-blue-500",
        autocomplete: "off"
      )
      if @show_discount_rate
        span(class: "text-xs text-gray-500") { plain("折現率") }
        input(
          id: "dr-input",
          type: "number",
          value: @discount_rate,
          min: "6", max: "20", step: "0.5",
          class: "w-16 rounded border border-gray-200 px-2 py-1.5 text-sm text-center"
        )
        span(class: "text-xs text-gray-500") { plain("%") }
      end
      button(
        type: "submit",
        class: "bg-blue-600 text-white text-sm px-4 py-1.5 rounded-lg hover:bg-blue-700 transition-colors"
      ) { plain(@button_text) }
    end
  end

  def discount_rate_slider
    div(class: "space-y-1") do
      div(class: "flex justify-between items-center") do
        label(for: "dr-input", class: "text-sm text-gray-600 font-medium") { plain("折現率（必要報酬率）") }
        span(id: "dr-display", class: "text-sm font-semibold text-blue-600") { plain("#{@discount_rate}%") }
      end
      input(
        id: "dr-input",
        type: "range",
        min: "6", max: "20", step: "0.5",
        value: @discount_rate,
        class: "w-full accent-blue-600"
      )
      div(class: "flex justify-between text-xs text-gray-400") do
        span { plain("6% 保守") }
        span { plain("10% 標準") }
        span { plain("20% 激進") }
      end
    end
  end

  def inline_script
    script do
      raw <<~JS.html_safe
        (function() {
          var form = document.getElementById('ticker-form');
          if (!form) return;
          form.addEventListener('submit', function(e) {
            e.preventDefault();
            var ticker = (document.getElementById('ticker-input').value || '').trim().toUpperCase();
            if (!ticker) { document.getElementById('ticker-input').focus(); return; }
            var dr = document.getElementById('dr-input');
            var rate = dr ? dr.value : '10';
            window.location.href = '/valuations/' + encodeURIComponent(ticker) + '?discount_rate=' + rate;
          });
          var slider = document.getElementById('dr-input');
          if (slider && slider.type === 'range') {
            slider.addEventListener('input', function() {
              var display = document.getElementById('dr-display');
              if (display) display.textContent = this.value + '%';
            });
          }
        })();
      JS
    end
  end
end
