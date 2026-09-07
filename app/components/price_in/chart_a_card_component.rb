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
    end
  end

  private

  def header
    div(class: "px-5 py-3 bg-indigo-800") do
      p(class: "text-[22px] font-medium text-white") do
        plain("#{PriceIn::Formatter.money(@result.price)}，需要多少盈利？")
      end
      p(class: "text-[16px] text-indigo-200") { plain("Fixed share price. Different earnings requirements.") }
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

  # 色帶說明（導覽步驟 9 的錨點）。與判讀卡分開：這一句講的是「這次這張圖有沒有色帶」，
  # 判讀卡講的是「色帶怎麼讀」。
  def band_note
    div(class: "px-5 py-3 border-t border-indigo-200", data: { tour_step: 9 }) do
      p(class: "text-[20px] text-indigo-900") do
        if @result.band?
          plain("色帶是 #{@form.eps_band_label}（#{PriceIn::Formatter.money(@result.band_low)}–" \
                "#{PriceIn::Formatter.money(@result.band_high)}）。落在色帶左側的倍數，代表現有預測撐得住。")
        else
          plain("填入 EPS 預測區間後，這裡會標出哪些倍數是現有預測撐得住的。")
        end
      end
    end
  end
end
