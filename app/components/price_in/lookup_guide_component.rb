# frozen_string_literal: true

# 收摺式查詢指引（規格 §S4）。原生 <details>/<summary>，不引入第三方 accordion。
#
# 網址中的代號用表單當前 ticker 動態代入——清單中所有網址都只需換代號，
# 不含需要產業分類或公司全名的路徑。寫死 MRVL 的連結在換股之後會把人帶到錯的頁面。
class PriceIn::LookupGuideComponent < ApplicationComponent
  LOCALE = PriceIn::FieldHelpCardComponent::LOCALE

  def initialize(key:, ticker:)
    @ticker = ticker.presence || "MRVL"
    @guide  = I18n.t("price_in.lookup.#{key}", locale: LOCALE)
  end

  def view_template
    details(class: "mt-4 rounded-lg border border-gray-300 bg-white/70 overflow-hidden") do
      summary(class: "min-h-[44px] flex items-center justify-between px-4 py-2 cursor-pointer text-[20px] font-medium text-gray-800 select-none") do
        span { plain(@guide[:summary]) }
        span(class: "text-gray-400 text-[16px]") { plain("▾") }
      end
      div(class: "border-t border-gray-300 px-4 py-3 space-y-4") do
        steps_block if @guide[:steps]
        kinds_block if @guide[:kinds]
        sources_block
        formula_block if @guide[:formula]
        pitfalls_block if @guide[:pitfalls]
        checks_block  if @guide[:checks]
      end
    end
  end

  private

  def heading(text)
    p(class: "text-[20px] font-medium text-gray-900") { plain(text) }
  end

  def steps_block
    heading(@guide[:steps_title])
    ol(class: "list-decimal pl-6 space-y-1") do
      @guide[:steps].each { |s| li(class: "text-[20px] leading-[1.6] text-gray-700") { plain(s) } }
    end
  end

  def kinds_block
    heading(@guide[:kinds_title])
    simple_table(%w[來源 特性 適合什麼情境], @guide[:kinds].map { |k| [ k[:source], k[:trait], k[:fit] ] })
  end

  def sources_block
    heading(@guide[:sources_title])
    table(class: "w-full text-[20px]") do
      thead do
        tr(class: "border-b border-gray-300 text-left text-gray-500") do
          %w[站點 網址 拿得到什麼].each { |h| th(class: "py-2 pr-3 font-medium") { plain(h) } }
        end
      end
      tbody do
        @guide[:sources].each { |src| source_row(src) }
      end
    end
    p(class: "text-[16px] text-gray-500 leading-[1.6]") { plain(@guide[:sources_note]) }
  end

  def source_row(src)
    tr(class: "border-b border-gray-100 hover:bg-gray-50 align-top") do
      td(class: "py-2 pr-3") { plain(src[:site]) }
      td(class: "py-2 pr-3") do
        url = build_url(src[:url])
        a(href: url, target: "_blank", rel: "noopener noreferrer",
          class: "font-mono text-[16px] text-blue-700 underline break-all") { plain(url) }
      end
      td(class: "py-2 text-gray-700 leading-[1.6]") { plain(src[:gets]) }
    end
  end

  def build_url(template)
    Kernel.format(template.to_s, ticker: @ticker, ticker_downcase: @ticker.downcase)
  end

  def formula_block
    heading(@guide[:formula_title])
    pre(class: "bg-gray-900 text-gray-100 rounded-lg px-4 py-3 font-mono text-[16px] overflow-x-auto") do
      plain(@guide[:formula])
    end
    ul(class: "list-disc pl-6 space-y-1") do
      @guide[:formula_notes].each { |n| li(class: "text-[20px] leading-[1.6] text-gray-700") { plain(n) } }
    end
  end

  def pitfalls_block
    heading(@guide[:pitfalls_title])
    simple_table(%w[坑 後果 怎麼避免], @guide[:pitfalls].map { |p| [ p[:pit], p[:effect], p[:avoid] ] })
  end

  def checks_block
    heading(@guide[:checks_title])
    simple_table(%w[核對點 為什麼重要], @guide[:checks].map { |c| [ c[:point], c[:why] ] })
  end

  def simple_table(headers, rows)
    table(class: "w-full text-[20px]") do
      thead do
        tr(class: "border-b border-gray-300 text-left text-gray-500") do
          headers.each { |h| th(class: "py-2 pr-3 font-medium") { plain(h) } }
        end
      end
      tbody do
        rows.each do |cells|
          tr(class: "border-b border-gray-100 hover:bg-gray-50 align-top") do
            cells.each { |c| td(class: "py-2 pr-3 text-gray-700 leading-[1.6]") { plain(c) } }
          end
        end
      end
    end
  end
end
