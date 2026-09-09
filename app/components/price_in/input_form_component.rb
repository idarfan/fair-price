# frozen_string_literal: true

# 輸入卡。情境狀態走 query string，所以是 GET 表單——送出後網址就是可分享的情境。
#
# 每個欄位群組上方置一張說明卡（規格 §S4）：使用者要看得懂每一個欄位在問什麼、
# 填錯會怎樣。說明文案全部來自 locale 檔，元件內不硬編句子。
class PriceIn::InputFormComponent < ApplicationComponent
  NARROW = PriceIn::PageComponent::NARROW

  # valuation 為 PriceIn::QuoteFetcher::Result 或 nil。有值代表使用者按過
  # 「帶入現價」且快取還在，估值對照就能在伺服器端直接渲染——否則按一次
  # 「重新出圖」（整頁 GET）就會把 JS 記憶體裡的數字全變成破折號。
  def initialize(form:, valuation: nil)
    @form      = form
    @valuation = valuation
  end

  def view_template
    div(class: NARROW.to_s + " mb-8") do
      form(
        action: "/price_in", method: "get", class: "space-y-6",
        data: { behavior: "price-in-ticker", quote_url: "/price_in/quote" }
      ) do
        # price_as_of 走隱藏欄位：它不是使用者填的，但必須跟著情境進 query string，
        # 否則重新出圖之後「報價時間」會憑空變成「手動輸入」。
        input(type: "hidden", name: "price_as_of", id: "price-in-price-as-of",
              value: @form.price_as_of&.iso8601)
        # 帶入現價時記下的 TTM EPS。只用來判定使用者填的倍數是不是現價反推的那一個，
        # 不參與任何估值計算——所以走隱藏欄位而不是佔一格版面。
        input(type: "hidden", name: "eps_ttm_hint", id: "price-in-eps-ttm-hint",
              value: @form.eps_ttm_hint&.to_s)
        ticker_group
        price_group
        multiples_group
        fiscal_year_group
        eps_band_group
        eps_group
        entry_group
        holding_group
        submit_row
      end
    end
  end

  private

  # ── 欄位群組 ────────────────────────────────────────────

  def ticker_group
    help(:ticker)
    fields do
      div(class: "grid grid-cols-1 sm:grid-cols-2 gap-4") do
        text_field(:ticker, "股票代號", placeholder: "MRVL")
        div(class: "flex items-end gap-3") do
          button(
            type: "button", id: "price-in-fetch-quote",
            class: "px-4 py-2 rounded-lg bg-slate-700 text-white text-[20px] hover:bg-slate-800"
          ) { plain("帶入現價") }
        end
      end
      p(id: "price-in-quote-status", class: "mt-2 text-[16px] text-gray-500") { plain(@form.price_source_label) }
      p(class: "mt-1 text-[16px] text-gray-400") do
        plain("頁面載入時不自動抓價——這是估值工具，不是報價看板。")
      end
    end
  end

  def price_group
    help(:price)
    fields(tour_step: 2) { number_field(:price, "股價", step: "0.01", placeholder: "223.55") }
  end

  def multiples_group
    help(:multiples) { reference_multiples }
    fields(tour_step: 3) do
      div(class: "grid grid-cols-1 sm:grid-cols-[1fr_auto] gap-4 items-end") do
        text_field(:chart_a_multiples, "本益比假設（逗號分隔，1–5 個）",
                   value: multiples_value(@form.chart_a_multiples, @form.chart_a_multiples_provided?),
                   placeholder: default_multiples_hint(PriceIn::ScenarioForm::DEFAULT_CHART_A_MULTIPLES))
        current_pe_panel
      end
    end
  end

  def fiscal_year_group
    help(:fiscal_year)
    fields(tour_step: 4) { text_field(:fiscal_year_label, "哪一年的 EPS", placeholder: "FY2028") }
  end

  def eps_band_group
    help(:eps_band) { render PriceIn::LookupGuideComponent.new(key: :eps_band, ticker: @form.ticker) }
    fields(tour_step: 5) do
      div(class: "grid grid-cols-1 sm:grid-cols-3 gap-4") do
        number_field(:eps_band_low, "EPS 預測區間下限（選填）", step: "0.01")
        number_field(:eps_band_high, "EPS 預測區間上限（選填）", step: "0.01")
        text_field(:eps_band_label, "區間來源")
      end
      estimate_panel
    end
  end

  # 分析師 EPS 預測區間。與本益比一樣由「帶入現價」一併抓回來。
  #
  # 帶入的是 low／high 兩端而不是平均值：色帶要畫的是分歧程度，
  # 拿平均值會讓色帶縮成一條線，圖 A 就看不出「難不難」。
  def estimate_panel
    div(id: "price-in-estimate-panel", hidden: estimates_blank?,
        class: "mt-4 rounded-lg border border-emerald-300 bg-emerald-50/60 px-4 py-3") do
      p(class: "text-[16px] font-medium text-emerald-900 mb-1") { plain("分析師 EPS 預測") }
      # 兩顆各管一半，互不越界：上面那顆只動圖 A，下面那顆只動圖 B。
      # 標籤寫出去向——兩顆長得一樣的按鈕擺在一起，使用者沒有理由猜得到。
      estimate_row("本財政年度", "current", @valuation&.eps_estimate, target: "圖 A")
      estimate_row("下一財政年度", "next", @valuation&.eps_estimate_next, target: "圖 B")
      p(class: "mt-1 text-[16px] text-gray-400 leading-[1.4]") do
        plain("來源 Yahoo Finance．上面那顆只動圖 A 的預測區間與年度，下面那顆只動圖 B 的未來 EPS 與年度")
      end
    end
  end

  def estimates_blank?
    @valuation.nil? ||
      (!@valuation.eps_estimate.available? && !@valuation.eps_estimate_next.available?)
  end

  def estimate_row(label_text, key, est = nil, target: nil)
    usable = est&.available?

    div(class: "flex items-baseline justify-between gap-3 py-0.5") do
      span(id: "price-in-estimate-#{key}-label", class: "text-[16px] text-gray-600 shrink-0") do
        plain(usable ? estimate_label(label_text, est) : label_text)
        if target
          span(class: "ml-2 text-[16px] px-1.5 py-0.5 rounded bg-emerald-200 text-emerald-900") do
            plain("→ #{target}")
          end
        end
      end
      div(class: "flex items-center gap-2") do
        span(id: "price-in-estimate-#{key}", class: "text-[20px] font-bold text-gray-900") do
          plain(usable ? estimate_value_text(est, key) : "—")
        end
        button(
          type: "button", id: "price-in-apply-estimate-#{key}", hidden: !usable,
          data: estimate_data(est, usable),
          class: "px-2 py-0.5 rounded border border-emerald-400 bg-white text-[16px] text-emerald-800 hover:bg-emerald-100"
        ) { plain("帶入") }
      end
    end
  end

  # 圖 B 那列多顯示平均值：按下去填進未來 EPS 的就是它，
  # 只顯示區間卻填一個沒出現過的數字，使用者會以為填錯了。
  def estimate_value_text(est, key)
    range = "#{PriceIn::Formatter.money(est.low)} - #{PriceIn::Formatter.money(est.high)}"
    return range unless key == "next" && est.avg.present?

    "#{range}（平均 #{PriceIn::Formatter.money(est.avg)}）"
  end

  # 標題補上年度與分析師家數：光看「本財政年度」對不出是哪一年，
  # 而年度對不上正是最常見的 Price-in 誤判來源。
  def estimate_label(label_text, est)
    year = est.end_date.to_s[0, 4]
    return label_text if year.blank?

    analysts = est.analysts.present? ? "，#{est.analysts} 位分析師" : ""
    "#{label_text}（截至 #{year}#{analysts}）"
  end

  def estimate_data(est, usable)
    return {} unless usable

    # avg 給圖 B 用：它要的是單一盈利假設，取一致預期的平均值，
    # 用區間端點等於替使用者選了最樂觀或最悲觀的情境。
    { low: fmt2(est.low), high: fmt2(est.high), avg: est.avg.present? ? fmt2(est.avg) : nil,
      end_date: est.end_date.to_s, analysts: est.analysts.to_s }.compact
  end

  def eps_group
    help(:eps) { render PriceIn::LookupGuideComponent.new(key: :eps, ticker: @form.ticker) }
    fields(tour_step: 6) do
      div(class: "grid grid-cols-1 sm:grid-cols-2 gap-4") do
        number_field(:eps, "未來 EPS（選填）", step: "0.01", placeholder: "例如 11.02")
        text_field(:chart_b_fiscal_year_label, "哪一年的 EPS", placeholder: "FY2029")
      end
      div(class: "mt-4") do
        text_field(:chart_b_multiples, "圖 B 本益比假設",
                   value: multiples_value(@form.chart_b_multiples, @form.chart_b_multiples_provided?),
                   placeholder: default_multiples_hint(PriceIn::ScenarioForm::DEFAULT_CHART_B_MULTIPLES))
      end
    end
  end

  def entry_group
    help(:entry_prices)
    fields(tour_step: 7) do
      div(class: "grid grid-cols-1 sm:grid-cols-2 gap-4") do
        readonly_field("買入基準（跟隨上方股價）", @form.entry_a_price, id: "price-in-entry-a-mirror")
        number_field(:entry_b_price, "假設買入價", step: "0.01")
      end
    end
  end

  def holding_group
    help(:holding)
    fields do
      div(class: "grid grid-cols-1 sm:grid-cols-3 gap-4") do
        number_field(:holding_years, "持有年數（選填）", step: "0.1")
        number_field(:discount_rate, "折現率（選填，0–1）", step: "0.01")
        number_field(:discount_years, "折現年數（選填）", step: "0.1")
      end
    end
  end

  # 三個估值對照數字，置於倍數欄位右側。
  #
  # 值由「帶入現價」一併抓回來，因此頁面初載全是破折號——這是估值工具不是報價看板，
  # 不主動抓價，本益比自然也不會憑空出現。
  #
  # 「口徑」指的是 GAAP 還是 non-GAAP。non-GAAP 把股權薪酬、併購無形資產攤銷等
  # 扣掉，EPS 幾乎永遠較高、本益比因而較低，兩者常差到倍數等級。上游沒有任何
  # 欄位說明它用哪一套，所以畫面直說「未標示」而不是猜一個標上去——這張圖的
  # 用途就是拆穿含糊的估值主張，自己先含糊就沒有立場。
  def current_pe_panel
    div(class: "rounded-lg border border-amber-300 bg-amber-50/60 px-4 py-3 min-w-[22rem]") do
      p(class: "text-[16px] font-medium text-amber-900 mb-1") { plain("估值對照") }
      pe_row("本益比 (P/E)", "price-in-current-pe",
             apply_id: "price-in-apply-pe", value: range_text(@valuation&.pe),
             apply_values: apply_values(@valuation&.pe))
      pe_row("預估本益比 (Forward P/E)", "price-in-forward-pe",
             apply_id: "price-in-apply-forward-pe", value: range_text(@valuation&.forward_pe),
             apply_values: apply_values(@valuation&.forward_pe))
      pe_row("產業平均本益比", "price-in-peer-pe", value: peer_text)
      p(id: "price-in-eps-basis", class: "mt-1 text-[16px] text-gray-400 leading-[1.4]") do
        plain(basis_text)
      end
    end
  end

  # 「帶入」把畫面上顯示的那組數字整組塞進倍數欄位：是區間就帶兩端。
  # 顯示兩個數字卻只帶一個進去，畫面會自相矛盾。
  #
  # 產業平均不給按鈕：它是「別人給的倍數」，不是「這檔股票現在的倍數」，
  # 拿來當自己的出價假設是另一回事。它的用途是讓你知道自己填的偏高還是偏低。
  def pe_row(label_text, value_id, apply_id: nil, value: "—", apply_values: nil)
    div(class: "flex items-baseline justify-between gap-3 py-0.5") do
      span(class: "text-[16px] text-gray-600 shrink-0") { plain(label_text) }
      div(class: "flex items-center gap-2") do
        span(id: value_id, class: "text-[20px] font-bold text-gray-900") { plain(value) }
        if apply_id
          button(
            type: "button", id: apply_id, hidden: apply_values.blank?,
            data: { pe: apply_values }.compact,
            class: "px-2 py-0.5 rounded border border-amber-400 bg-white text-[16px] text-amber-800 hover:bg-amber-100"
          ) { plain("帶入") }
        end
      end
    end
  end

  # 區間文字。伺服器端與 JS 端（priceInTicker.ts 的 formatRange）必須給出
  # 同樣的格式，否則「重新出圖」前後同一個數字會換一種寫法。
  def range_text(range)
    return "—" if range.nil?
    return "#{fmt2(range.low)} - #{fmt2(range.high)}x" if range.low && range.high
    return "#{fmt2(range.current)}x" if range.current

    "—"
  end

  def apply_values(range)
    return nil if range.nil?
    return [ fmt2(range.low), fmt2(range.high) ].join(",") if range.low && range.high
    return fmt2(range.current) if range.current

    nil
  end

  def peer_text
    low  = @valuation&.peer_low
    high = @valuation&.peer_high
    return "—" if low.nil? || high.nil?

    "#{fmt2(low)} - #{fmt2(high)}x"
  end

  def basis_text
    eps = @valuation&.eps_ttm
    return "上游未標示 GAAP 或非 GAAP，僅供對照" if eps.nil?

    "以 TTM EPS #{PriceIn::Formatter.money(eps)} 換算當日價格區間．上游未標示 GAAP 或非 GAAP"
  end

  def fmt2(value) = Kernel.format("%.2f", value.to_f)

  # ── 參考倍數（唯讀，嚴禁自動填入輸入框）────────────────

  def reference_multiples
    div(class: "mt-4 rounded-lg border border-amber-300 bg-white/70 px-4 py-3") do
      p(class: "text-[20px] font-medium text-amber-900 mb-2") { plain("參考倍數（唯讀，不會填進輸入框）") }
      div(class: "grid grid-cols-1 sm:grid-cols-2 gap-4") do
        reference_cell("現價隱含倍數（#{@form.fiscal_year_label}）", band_implied_multiple, "以你填的預期 EPS 區間反推")
        reference_cell("現價隱含倍數（#{@form.chart_b_fiscal_year_label}）", eps_implied_multiple, "以你填的假設 EPS 反推")
      end
    end
  end

  def reference_cell(label, value, note)
    div do
      p(class: "text-[16px] text-gray-500") { plain(label) }
      p(class: "text-[24px] font-bold text-gray-900") { plain(value) }
      p(class: "text-[16px] text-gray-400") { plain(note) }
    end
  end

  # 區間兩端各算一次，顯示為區間。任一端留空就顯示破折號，不顯示錯誤。
  def band_implied_multiple
    low  = PriceIn::RequiredEpsCalculator.implied_multiple(@form.price, @form.eps_band_high)
    high = PriceIn::RequiredEpsCalculator.implied_multiple(@form.price, @form.eps_band_low)
    return "—" if low.nil? || high.nil?

    "#{PriceIn::Formatter.multiple(low)} – #{PriceIn::Formatter.multiple(high)}"
  end

  def eps_implied_multiple
    PriceIn::Formatter.multiple(PriceIn::RequiredEpsCalculator.implied_multiple(@form.price, @form.eps))
  end

  # 使用者沒填就讓欄位真的空著，預設值只放在 placeholder。
  # 預先塞值的話，按「帶入」會變成預設值加上帶入的兩個數字一長串，
  # 而使用者從沒打算保留那些預設值。
  def multiples_value(list, provided)
    return "" unless provided

    list.map { |m| Kernel.format("%g", m) }.join(",")
  end

  def default_multiples_hint(defaults)
    "留空則使用 #{defaults.map { |m| Kernel.format('%g', m) }.join('、')}"
  end

  # ── 版面小工具 ──────────────────────────────────────────

  def help(key, &block)
    render PriceIn::FieldHelpCardComponent.new(key: key, ticker: @form.ticker), &block
  end

  # tour_step 掛在輸入欄位的容器上，不是說明卡上——導覽要指的是「這一格要填什麼」，
  # 指到說明卡會讓 popover 蓋住使用者正要看的輸入框。
  def fields(tour_step: nil, &)
    div(class: "rounded-xl border border-gray-300 bg-white px-5 py-4 mb-6",
        data: { tour_step: tour_step }.compact, &)
  end

  def submit_row
    div(class: "pt-2") do
      button(type: "submit", class: "px-5 py-2.5 rounded-lg bg-blue-600 text-white text-[20px] hover:bg-blue-700") do
        plain("重新出圖")
      end
    end
  end

  def text_field(name, label_text, value: nil, placeholder: nil)
    field_wrapper(label_text) do
      input(type: "text", name: name.to_s, id: "price-in-#{name}",
            value: value || @form.public_send(name).to_s, placeholder: placeholder,
            class: input_class)
    end
  end

  def number_field(name, label_text, step: "0.01", placeholder: nil)
    field_wrapper(label_text) do
      input(type: "number", name: name.to_s, id: "price-in-#{name}", step: step,
            value: @form.public_send(name)&.to_s, placeholder: placeholder,
            class: input_class)
    end
  end

  # 買入基準恆等於股價（entry_a_link_price 預設 true），因此不給獨立輸入框——
  # 兩個欄位並列會讓人以為可以各填各的，然後兩張圖就在講不同的價格。
  def readonly_field(label_text, value, id: nil)
    field_wrapper(label_text) do
      input(type: "text", id: id, value: PriceIn::Formatter.money(value), readonly: true,
            class: "#{input_class} bg-gray-100 text-gray-500")
    end
  end

  def field_wrapper(label_text, &)
    div do
      label(class: "block text-[16px] text-gray-500 mb-1") { plain(label_text) }
      yield
    end
  end

  def input_class
    "w-full px-3 py-2 rounded-lg border border-gray-300 text-[20px] focus:border-blue-500 focus:outline-none"
  end
end
