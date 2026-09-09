# frozen_string_literal: true

# 兩張圖必須成組使用：圖 A 回答「多少盈利」，圖 B 回答「多少價格」，
# 缺一邊就會落回單點估值的錯覺。因此兩張圖同頁呈現，不拆成兩個路由。
#
# 版面：2026-09-07 依使用者要求改為全版面 96%，取代 v1 規格的 760／960px 上限。
# 兩者仍分成兩個常數，因為匯出（§S8）與畫面是脫鉤的，日後若要讓圖表卡與輸入卡
# 再度分寬，改這裡兩行就好，不必回頭找散落各處的 class。
class PriceIn::PageComponent < ApplicationComponent
  NARROW = "w-[96%] mx-auto"
  WIDE   = "w-[96%] mx-auto"

  def initialize(form:, chart_a: nil, chart_b: nil, audit: {}, valuation: nil, logo: nil)
    @form      = form
    @chart_a   = chart_a
    @chart_b   = chart_b
    @audit     = audit || {}
    @valuation = valuation
    @logo      = logo
  end

  # 說明卡的實例表格。用使用者當前的股價與倍數算，不用寫死的範例——
  # 抽象規則看得懂不代表套得到自己的情境。
  def logic_example
    PriceIn::LogicExampleBuilder.call(
      price:             @form.price,
      multiples:         @form.chart_a_multiples,
      band_low:          @form.eps_band_low,
      band_high:         @form.eps_band_high,
      fiscal_year_label: @form.fiscal_year_label,
      implied_current:   PriceIn::RequiredEpsCalculator.implied_multiple(@form.price, @form.eps_ttm_hint)
    )
  end

  def view_template
    div(
      id: "price-in-root",
      class: "flex-1 min-w-0 bg-gray-50 py-8 text-[20px] text-gray-800",
      data: { behavior: "price-in-export", help_visible: "false", reading_visible: "false" }
    ) do
      render_header
      render_errors if @form.errors.any?
      render_warnings if @form.warnings.any?
      render PriceIn::ReadingNoteComponent.new(key: "price_in_logic", worked_example: logic_example)
      render PriceIn::InputFormComponent.new(form: @form, valuation: @valuation)
      render_charts
      tour_data_island
      export_islands
    end
  end

  private

  def render_header
    div(class: "#{WIDE} mb-6 flex items-start justify-between gap-4") do
      div(data: { tour_step: 1 }) do
        p(class: "text-[16px] tracking-widest text-gray-400 uppercase") { plain("Price In") }
        h1(class: "text-[22px] font-medium text-gray-900") do
          plain("#{@form.ticker}：這個價格正在要求公司賺到多少？")
        end
        p(class: "mt-1 text-[20px] text-gray-500") do
          plain("把「已經 price in 太多了」拆成三個可填欄位：哪一年的 EPS、給幾倍、從什麼價格買進。")
        end
      end
      tour_buttons
    end
  end

  # 兩個布林開關，不是一次性動作按鈕。按下＝顯示對應的說明卡，再按一次收起。
  # 按下與未按下用底色區分（深色實心 vs 白底外框），並以 aria-pressed 讓輔助技術
  # 也讀得出狀態——單靠顏色表達狀態對色覺障礙使用者無效。
  #
  # 逐步導覽（driver.js）改成開關打開後才出現的次要按鈕：它是「看完說明還想被
  # 一步步帶」的人才需要的，放在頁首常駐會讓三顆按鈕互相搶注意力。
  def tour_buttons
    div(
      class: "flex items-center gap-2 shrink-0",
      data: {
        behavior:     "price-in-tour",
        read_ready:   @chart_b.present?.to_s,
        eps_field_id: "price-in-eps"
      }
    ) do
      button(type: "button", id: "price-in-toggle-help",
             aria: { pressed: "false" }, class: toggle_btn_class) { plain(tour_t(:button_input)) }
      button(type: "button", id: "price-in-toggle-reading",
             aria: { pressed: "false" }, class: toggle_btn_class) do
        plain(@chart_b.present? ? tour_t(:button_read) : tour_t(:button_read_disabled))
      end
      # 只在「輸入導覽」打開後才出現：它是看完說明還想被一步步帶的人才需要的，
      # 常駐頁首會讓三顆按鈕互相搶注意力。
      button(type: "button", id: "price-in-tour-start", hidden: true,
             class: "px-3 py-2 rounded-lg border border-blue-300 bg-blue-50 text-[16px] " \
                    "text-blue-700 hover:bg-blue-100") do
        plain(tour_t(:button_walkthrough))
      end
    end
  end

  # 未按下的樣式。按下時由前端換成 TOGGLE_ON（兩者都在這裡定義，
  # 讓「開」與「關」長什麼樣可以並排比對）。
  TOGGLE_OFF = "px-3 py-2 rounded-lg border border-gray-300 bg-white text-[16px] text-gray-700 hover:bg-gray-50"
  TOGGLE_ON  = "px-3 py-2 rounded-lg border border-slate-700 bg-slate-700 text-[16px] text-white hover:bg-slate-800"

  def toggle_btn_class = TOGGLE_OFF

  def tour_t(key) = I18n.t("price_in.tour.#{key}", locale: PriceIn::FieldHelpCardComponent::LOCALE)

  # 導覽文案走資料島而不是 data attribute：13 步的文字塞進屬性會讓 DOM 難以閱讀。
  # json_escape 防止文案中的 < 提前關閉標籤。
  # 匯出用的文案與稽核結果。走資料島而非 data attribute：文案有十幾條，
  # 塞進屬性會讓 DOM 難以閱讀，而稽核結果是結構化的陣列。
  def export_islands
    json_island("price-in-export-i18n", I18n.t("price_in.export", locale: LOCALE_KEY))
    @audit.each do |key, hits|
      json_island("price-in-audit-#{key}", hits.map(&:to_h))
    end
  end

  def json_island(dom_id, payload)
    script(type: "application/json", id: dom_id) do
      raw(ERB::Util.json_escape(payload.to_json).html_safe)
    end
  end

  LOCALE_KEY = PriceIn::FieldHelpCardComponent::LOCALE

  def tour_data_island
    steps = I18n.t("price_in.tour.steps", locale: PriceIn::FieldHelpCardComponent::LOCALE)
    script(type: "application/json", id: "price-in-tour-data") do
      raw(ERB::Util.json_escape(steps.to_json).html_safe)
    end
  end


  def render_errors
    div(class: "#{NARROW} mb-6") do
      div(class: "rounded-xl border border-red-300 bg-red-50 overflow-hidden") do
        div(class: "px-4 py-2 bg-red-100 border-b border-red-200") do
          p(class: "text-[22px] font-medium text-red-800") { plain("這些欄位需要修正") }
        end
        ul(class: "px-6 py-3 list-disc space-y-1") do
          @form.errors.full_messages.each { |msg| li(class: "text-[20px] text-red-700") { plain(msg) } }
        end
      end
    end
  end

  def render_warnings
    div(class: "#{NARROW} mb-6") do
      div(class: "rounded-xl border border-amber-300 bg-amber-50 px-4 py-3") do
        @form.warnings.each { |msg| p(class: "text-[20px] text-amber-800") { plain(msg) } }
      end
    end
  end

  def render_charts
    return unless @form.errors.empty?

    render PriceIn::ChartACardComponent.new(form: @form, result: @chart_a, logo: @logo)
    render PriceIn::ChartBCardComponent.new(form: @form, result: @chart_b)
  end
end
