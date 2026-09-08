# frozen_string_literal: true

# 圖 B：固定未來 EPS，變動本益比假設 × 買入價。
# 關鍵讀法——同一列兩條長條的落差 = 買入價的代價。
#
# EPS 留空時顯示空狀態而非錯誤：圖 A 與圖 B 是兩組獨立輸入，
# 只填圖 A 的人不該因為沒填 EPS 就看不到任何東西。
class PriceIn::ChartBCardComponent < ApplicationComponent
  CANVAS_ID = "price-in-chart-b"
  WIDE      = PriceIn::PageComponent::WIDE

  def initialize(form:, result:)
    @form   = form
    @result = result
  end

  def view_template
    div(class: "#{WIDE} mb-8") do
      div(class: "rounded-xl border border-teal-300 bg-teal-50/40 overflow-hidden") do
        header
        @result.nil? ? empty_state : filled_state
      end
      if @result
        render PriceIn::ExportCardComponent.new(
          key: "chart_b", form: @form, title: TITLE, subtitle: SUBTITLE,
          source_canvas_id: CANVAS_ID, eps_banner: export_banner
        )
      end
    end
  end

  private

  TITLE    = "同樣兌現盈利，報酬為什麼不同？"
  SUBTITLE = "Same earnings. Different entry prices."

  def header
    div(class: "px-5 py-3 bg-teal-800 flex items-center justify-between gap-4") do
      div do
        p(class: "text-[22px] font-medium text-white") { plain(TITLE) }
        p(class: "text-[16px] text-teal-200") { plain(SUBTITLE) }
      end
      render PriceIn::ExportButtonsComponent.new(key: "chart_b") if @result
    end
  end

  # 匯出版的 EPS 橫幅（規格 §S6）。統一假設的年度與 EPS 必須寫在圖上，
  # 否則成品圖脫離頁面後就看不出這個報酬是在假設誰賺多少。
  def export_banner
    "未來估值時點：統一假設 #{@form.chart_b_fiscal_year_label} 調整後 EPS = " \
      "#{PriceIn::Formatter.money(@result.eps)}"
  end

  def empty_state
    div(class: "px-5 py-8 bg-white text-center") do
      p(class: "text-[20px] text-gray-600") { plain("填入「未來 EPS」後，這裡會畫出同樣盈利在不同買入價下的報酬差距。") }
      p(class: "mt-2 text-[16px] text-gray-400") { plain("這一區留空不影響圖 A。") }
    end
  end

  def filled_state
    div(class: "px-5 py-4 bg-white") do
      div(class: "relative h-[320px] mb-4") do
        canvas(
        id: CANVAS_ID,
        data: {
          behavior: "price-in-chart-b",
          tour_step: 11,
          "chart_b_payload": chart_payload.to_json
        }
      )
      end
      render_table
      render PriceIn::ReadingNoteComponent.new(key: "chart_b")
    end
  end

  # payload 走 data attribute（規格 §S5／§S6 的驗證指令直接 grep 這個屬性）。
  # Phlex 會把屬性值做 HTML escape，引號變成 &quot;，因此使用者輸入的字串
  # 無法逃逸成標籤；JS 端用 dataset 讀回來是還原後的原字串。
  def chart_payload
    {
      eps:        @result.eps,
      fiscalYear: @form.chart_b_fiscal_year_label,
      entryA:     { price: @form.entry_a_price, label: @form.entry_a_label },
      entryB:     { price: @form.entry_b_price, label: @form.entry_b_label },
      rows:       @result.rows.map do |r|
        { multiple: r.multiple, targetPrice: r.target_price,
          returns: r.cells.map { |c| { entryPrice: c.entry_price, totalReturn: c.total_return } } }
      end
    }
  end

  def render_table
    table(class: "w-full text-[20px]", data: { tour_step: 13 }) do
      thead do
        tr(class: "border-b border-gray-300 text-left text-gray-500") do
          th(class: "py-2 font-medium") { plain("本益比") }
          th(class: "py-2 font-medium") { plain("目標價") }
          th(class: "py-2 font-medium") { plain(@form.entry_a_label) }
          th(class: "py-2 font-medium") { plain(@form.entry_b_label) }
        end
      end
      tbody do
        # 步驟 12 指向倍數最高那一列——落差最大，最能看出買入價的代價。
        highest = @result.rows.max_by(&:multiple)
        @result.rows.each { |row| render_row(row, tour: row.equal?(highest)) }
      end
    end
  end

  def render_row(row, tour: false)
    tr(class: "border-b border-gray-100", data: { tour_step: (12 if tour) }.compact) do
      td(class: "py-2") { plain(row.formatted_multiple) }
      td(class: "py-2") { plain(row.formatted_target) }
      row.cells.each do |cell|
        td(class: "py-2 text-[24px] font-bold #{return_color(cell.total_return)}") do
          plain(cell.formatted_return)
          if cell.annualized
            span(class: "block text-[16px] font-normal text-gray-500") do
              plain("年化 #{cell.formatted_annualized}")
            end
          end
        end
      end
    end
  end

  def return_color(value)
    return "text-gray-500" if value.nil?

    value.negative? ? "text-red-600" : "text-green-700"
  end
end
