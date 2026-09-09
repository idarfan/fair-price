# frozen_string_literal: true

# 圖 A：固定股價，變動本益比假設。
# 關鍵讀法——圓點落在色帶左側 = 現有預測撐得住。
class PriceIn::ChartACardComponent < ApplicationComponent
  CANVAS_ID = "price-in-chart-a"
  WIDE      = PriceIn::PageComponent::WIDE

  def initialize(form:, result:)
    @form   = form
    @result = result
  end

  def view_template
    return if @result.nil?

    div(class: "#{WIDE} mb-8") do
      div(class: "rounded-xl border border-indigo-300 bg-indigo-50/40 overflow-hidden") do
        header
        div(class: "px-5 py-4 bg-white") do
          canvas_slot
          render_table
          render PriceIn::ReadingNoteComponent.new(key: "chart_a")
        end
        band_note
      end
      render PriceIn::ExportCardComponent.new(
        key: "chart_a", form: @form, title: title, subtitle: SUBTITLE,
        source_canvas_id: CANVAS_ID, eps_banner: export_banner
      )
    end
  end

  private

  TITLE_SUFFIX = "，需要多少盈利？"
  SUBTITLE     = "Fixed share price. Different earnings requirements."

  def title = "#{PriceIn::Formatter.money(@result.price)}#{TITLE_SUFFIX}"

  # 匯出版的 EPS 橫幅：把年度與色帶來源寫進圖裡。缺年度的圖會誤導，
  # 而匯出的圖脫離頁面之後沒有任何其他線索可以補回這個資訊。
  def export_banner
    base = "#{@form.fiscal_year_label} 需要的 EPS"
    return base unless @result.band?

    "#{base}｜色帶 #{PriceIn::Formatter.money(@result.band_low)}–" \
      "#{PriceIn::Formatter.money(@result.band_high)}（#{@form.eps_band_label}）"
  end

  def header
    div(class: "px-5 py-3 bg-indigo-800 flex items-center justify-between gap-4") do
      div do
        p(class: "text-[22px] font-medium text-white") { plain(title) }
        p(class: "text-[16px] text-indigo-200") { plain(SUBTITLE) }
      end
      render PriceIn::ExportButtonsComponent.new(key: "chart_a")
    end
  end

  # 實際繪圖在 S5 接上 Chart.js；容器與資料島先就位。
  def canvas_slot
    div(class: "relative h-[320px] mb-4") do
      canvas(
        id: CANVAS_ID,
        data: {
          behavior: "price-in-chart-a",
          tour_step: 8,
          "chart_a_payload": chart_payload.to_json
        }
      )
    end
  end

  # payload 走 data attribute（規格 §S5／§S6 的驗證指令直接 grep 這個屬性）。
  # Phlex 會把屬性值做 HTML escape，引號變成 &quot;，因此使用者輸入的字串
  # 無法逃逸成標籤；JS 端用 dataset 讀回來是還原後的原字串。
  def chart_payload
    {
      fiscalYear: @form.fiscal_year_label,
      bandLow:    @result.band_low,
      bandHigh:   @result.band_high,
      bandLabel:  @form.eps_band_label,
      rows:       @result.rows.map { |r| { multiple: r.multiple, requiredEps: r.required_eps } }
    }
  end

  def render_table
    table(class: "w-full text-[20px]") do
      thead do
        tr(class: "border-b border-gray-300 text-left text-gray-500") do
          th(class: "py-2 font-medium") { plain("本益比假設") }
          th(class: "py-2 font-medium") { plain("#{@form.fiscal_year_label} 需要的 EPS") }
        end
      end
      tbody do
        # 步驟 10 指向「最長的橫條」＝所需 EPS 最高那一列＝倍數最低那一列。
        longest = @result.rows.min_by(&:multiple)
        @result.rows.each do |row|
          tr(class: "border-b border-gray-100",
             data: { tour_step: (10 if row.equal?(longest)) }.compact) do
            td(class: "py-2") { plain(row.formatted_multiple) }
            td(class: "py-2 text-[24px] font-bold text-gray-900") { plain(row.formatted_eps) }
          end
        end
      end
    end
  end

  # 圖例＋色帶說明（導覽步驟 9 的錨點）。
  #
  # 原本只寫「色帶是⋯落在色帶左側的倍數」，看圖的人分不出「色帶」指的是
  # 綠色那塊還是灰藍橫條，而且落在左側的是圓點不是倍數。三個視覺元素各給
  # 一個色塊直接對應，比任何文字描述都快。
  def band_note
    div(class: "px-5 py-3 border-t border-indigo-200", data: { tour_step: 9 }) do
      legend
      p(class: "mt-2 text-[20px] text-indigo-900 leading-[1.6]") { plain(band_sentence) }
    end
  end

  def legend
    div(class: "flex flex-wrap items-center gap-x-6 gap-y-1 text-[16px] text-gray-600") do
      legend_item("pi-swatch-bar", "橫條＝這個倍數需要公司賺到的 EPS")
      legend_item("pi-swatch-dot", "圓點＝該 EPS 的位置")
      legend_item("pi-swatch-band", band_legend_label) if @result.band?
    end
  end

  def legend_item(swatch_class, text)
    span(class: "inline-flex items-center") do
      span(class: "pi-swatch #{swatch_class}")
      plain(text)
    end
  end

  def band_legend_label
    "綠色直帶＝分析師預測區間 #{PriceIn::Formatter.money(@result.band_low)}–" \
      "#{PriceIn::Formatter.money(@result.band_high)}"
  end

  def band_sentence
    unless @result.band?
      return "填入 EPS 預測區間後，圖上會出現一條綠色直帶，用來判斷這些倍數難不難達成。"
    end

    "圓點落在綠帶左側＝現有預測撐得住這個倍數；落在綠帶之中＝需要偏預測上緣；" \
      "落在綠帶右側＝需要盈利超出目前所有預測。區間來源：#{@form.eps_band_label}。"
  end
end
