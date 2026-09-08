# frozen_string_literal: true

# 「怎麼看這張圖」判讀說明卡，置於圖表下方（規格 §S5／§S6）。
#
# 沿用 §S4 的色帶卡片結構：深色標題色帶 ＋ 同色系最淺階卡身 ＋ 同色系中階邊框。
# 文案全部來自 locale，元件內不硬編句子。
class PriceIn::ReadingNoteComponent < ApplicationComponent
  LOCALE = PriceIn::FieldHelpCardComponent::LOCALE

  TONES = {
    "chart_a"        => { band: "bg-emerald-800", body: "bg-emerald-50/50", border: "border-emerald-300",
                          head: "text-emerald-900" },
    "chart_b"        => { band: "bg-orange-800",  body: "bg-orange-50/50",  border: "border-orange-300",
                          head: "text-orange-900" },
    "price_in_logic" => { band: "bg-slate-800",   body: "bg-slate-50",      border: "border-slate-300",
                          head: "text-slate-900" }
  }.freeze

  # worked_example 傳入時會在說明下方附一張「拿你目前填的數字跑一次」的表格。
  # 抽象規則看得懂不代表套得到自己的情境，而 price in 最常見的誤判
  # 正是把現價反推的倍數當成假設——用使用者自己的數字演一次最擋得住。
  def initialize(key:, worked_example: nil)
    @key     = key.to_s
    @note    = I18n.t("price_in.reading.#{@key}", locale: LOCALE)
    @tone    = TONES.fetch(@key, TONES["chart_a"])
    @example = worked_example
  end

  # 與欄位說明卡一樣預設收摺：圖已經畫出來了，判讀說明是「看不懂時才點開」的東西，
  # 不該把圖表推出畫面。
  # 顯示開關：判讀卡跟著「讀圖導覽」，但 price in 邏輯說明跟著「輸入導覽」——
  # 「讀圖導覽」在沒填 EPS 時是停用的（點了只捲到 EPS 欄位），
  # 掛在它底下的卡片永遠不會出現。
  def toggle_class = @key == "price_in_logic" ? "pi-help" : "pi-reading"

  def view_template
    details(class: "pi-card #{toggle_class} rounded-xl border #{@tone[:border]} overflow-hidden mt-4") do
      summary(class: "min-h-[44px] flex items-center gap-2 px-4 py-2 #{@tone[:band]} cursor-pointer select-none") do
        span(class: "text-[24px]") { plain(@note[:icon]) }
        p(class: "flex-1 text-[20px] font-medium text-white") { plain(@note[:title]) }
        span(class: "pi-chevron text-white/70 text-[16px] shrink-0") { plain("▾") }
      end
      ol(class: "px-4 py-4 #{@tone[:body]} border-t #{@tone[:border]} space-y-3 list-none") do
        Array(@note[:items]).each_with_index { |item, i| render_item(item, i) }
      end
      worked_example if @example.present?
    end
  end

  # 拿使用者當前的股價與倍數，逐列算出「需要的 EPS」，並標出哪一列是
  # 現價反推的倍數（那一列的結論一定是無效的循環論證）。
  def worked_example
    div(class: "px-5 pb-4 #{@tone[:body]}") do
      p(class: "text-[20px] font-medium #{@tone[:head]} mb-2") { plain("拿你目前填的數字跑一次") }
      table(class: "w-full text-[20px]") do
        thead do
          tr(class: "border-b border-gray-300 text-left text-gray-500") do
            [ "你給的倍數", "需要的 EPS", "判讀" ].each { |h| th(class: "py-2 pr-3 font-medium") { plain(h) } }
          end
        end
        tbody { @example[:rows].each { |row| example_row(row) } }
      end
      p(class: "mt-2 text-[16px] text-gray-500 leading-[1.6]") { plain(@example[:footnote]) }
    end
  end

  def example_row(row)
    tr(class: "border-b border-gray-200 align-top transition-colors hover:bg-yellow-100") do
      td(class: "py-2 pr-3") { plain(row[:multiple]) }
      td(class: "py-2 pr-3 font-bold") { plain(row[:required_eps]) }
      td(class: "py-2 #{row[:circular] ? 'text-red-700' : 'text-gray-700'} leading-[1.6]") do
        plain(row[:verdict])
      end
    end
  end

  private

  # 奇偶段落交替底色，讓段落之間一眼分得開；段落內每一句是獨立的一行，
  # 游標懸停時整行變淺黃——長段說明最容易發生的是「讀到一半跳行」，
  # 交替底色管段落、hover 管行，兩個層級各自解決一個問題。
  ITEM_TONES = [
    "bg-emerald-50 border-emerald-200",
    "bg-violet-50 border-violet-200"
  ].freeze

  ROW_HOVER = "px-2 py-1 rounded transition-colors hover:bg-yellow-100"

  def render_item(item, index)
    li(class: "rounded-lg border #{ITEM_TONES[index % 2]} px-3 py-2") do
      div(class: "text-[20px] #{@tone[:head]} font-medium leading-[1.6] #{ROW_HOVER}") do
        plain("#{index + 1}. #{item[:head]}")
      end
      div(class: "mt-1 font-normal text-gray-700") do
        # 一句一行（§S4 斷句規則）：locale 已切好，這裡只負責包 block。
        Array(item[:body]).each { |line| div(class: "leading-[1.6] #{ROW_HOVER}") { plain(line) } }
        render_bullets(item[:bullets]) if item[:bullets].present?
      end
    end
  end

  def render_bullets(bullets)
    ul(class: "mt-2 space-y-1") do
      bullets.each do |b|
        li(class: "leading-[1.6] pl-3 border-l-2 border-black/20 #{ROW_HOVER}") { plain(b) }
      end
    end
  end
end
