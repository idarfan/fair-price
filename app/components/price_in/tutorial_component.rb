# frozen_string_literal: true

# 頁面最底的教學說明（預設收摺）。
#
# 與 FieldHelpCardComponent／ReadingNoteComponent 的分工：
#   欄位說明卡 → 這一格要填什麼
#   判讀說明卡 → 這張圖怎麼看
#   本元件     → 這個工具在回答什麼問題，以及最容易誤讀的地方
#
# 存在的理由是 2026-09-09 實際看圖時踩到的三個誤讀：把圓點落在色帶左側當成
# 便宜、把現價反推的倍數當成市場的估值意願、把報酬全押在盈利達標而忽略倍數。
# 這三件事在欄位說明與判讀說明裡都講不完整——它們不屬於任何單一欄位或單一圖。
#
# 數字全部由 TutorialExample 用使用者當前填的欄位算出，不寫死範例：在一個
# 「拿你自己的數字演一次」的工具裡放別人的作業，等於自打嘴巴。
#
# 預設收摺（details 不帶 open）：它是通篇教學，常駐展開會把圖表推出畫面。
# 用 details/summary 而不是 button + JS：Phlex 2.x 封鎖 on* 事件屬性，
# 而這裡只需要開關，不需要與其他元件同步狀態。
class PriceIn::TutorialComponent < ApplicationComponent
  LOCALE = PriceIn::FieldHelpCardComponent::LOCALE

  def initialize(form:)
    @doc     = I18n.t("price_in.tutorial", locale: LOCALE)
    @example = PriceIn::TutorialExample.call(form: form)
  end

  def view_template
    div(class: "#{PriceIn::PageComponent::WIDE} mt-10 mb-4") do
      details(class: "rounded-xl border border-slate-300 overflow-hidden") do
        render_summary
        div(class: "px-5 py-5 bg-slate-50 border-t border-slate-300 space-y-6") do
          paragraph(@doc[:intro], css: "text-[20px] text-slate-600")
          paragraph(interpolate(@doc[:hint_quote]), css: "text-[20px] text-slate-500") unless all_ready?
          Array(@doc[:sections]).each { |spec| render_section(spec) }
        end
      end
    end
  end

  private

  def ready  = @example[:ready]
  def vars   = @example[:vars]
  def tables = @example[:tables]

  def all_ready? = ready.values.all?

  # 這一節要的資料齊了沒。requires 未宣告代表整節都是靜態文字，永遠顯示。
  def satisfied?(requires)
    Array(requires).all? { |key| ready[key.to_sym] }
  end

  # 代入使用者的數字。用 gsub 而不是 String#% ——文案裡有「±16%」這種
  # 字面的百分號，交給 format 會被當成格式指示字元而拋 ArgumentError。
  #
  # 找不到的 key 原樣留著而不是換成空字串：畫面上出現 %{foo} 一眼就知道
  # 是代入漏了，換成空字串則會變成一句讀起來通順但意思錯掉的話。
  def interpolate(text)
    text.to_s.gsub(/%\{(\w+)\}/) { vars[Regexp.last_match(1).to_sym]&.to_s || Regexp.last_match(0) }
  end

  def render_summary
    summary(class: "min-h-[44px] flex items-center gap-2 px-4 py-2 bg-slate-800 cursor-pointer select-none") do
      span(class: "text-[24px]") { plain(@doc[:icon]) }
      p(class: "flex-1 text-[20px] font-medium text-white") { plain(@doc[:title]) }
      span(class: "pi-chevron text-white/70 text-[16px] shrink-0") { plain("▾") }
    end
  end

  # 參數不叫 section：那會遮蔽 Phlex 的 <section> 元素方法，讀起來像 bug。
  def render_section(spec)
    section(class: "space-y-2") do
      h3(class: "text-[22px] font-medium text-slate-900") { plain(spec[:heading]) }
      satisfied?(spec[:requires]) ? render_body(spec) : render_fallback(spec)
    end
  end

  def render_body(spec)
    Array(spec[:body]).each { |line| paragraph(interpolate(line)) }
    render_table(tables[spec[:table].to_sym]) if spec[:table].present?
    Array(spec[:footer]).each { |line| paragraph(interpolate(line)) }
    render_extra(spec[:extra]) if spec[:extra].present?
    render_callout(interpolate(spec[:callout])) if spec[:callout].present?
  end

  # 「有了 TTM EPS 才講得出來」的補充，與整節的 requires 分開判定：
  # 第五節只要有 EPS 錨就畫得出表，但「倍數與盈利不可能並存」那句話
  # 還需要知道目前實際賺多少。
  def render_extra(extra)
    return unless satisfied?(extra[:requires])

    Array(extra[:lines]).each { |line| paragraph(interpolate(line)) }
  end

  # 資料不齊時只說「補什麼就會算給你看」，不顯示半套數字——
  # 半套數字比沒有更容易誤導。
  def render_fallback(spec)
    div(class: "rounded-lg border border-dashed border-slate-300 bg-white px-4 py-3") do
      paragraph(interpolate(spec[:fallback]), css: "text-[20px] text-slate-500")
    end
  end

  # 關鍵字不叫 class：那會遮蔽 Kernel#class，只能靠 binding 取回，讀起來像陷阱。
  def paragraph(line, css: "text-[20px] text-slate-700 leading-[1.6]")
    p(class: css) { plain(line) }
  end

  # 表格一律可橫向捲動：教學說明是全版面 96% 的區塊，但視窗縮到手機寬度時
  # 三欄數字仍會撐破容器，讓整頁出現水平捲軸。
  #
  # spec 為 nil 代表算不出這張表（例如兩個買入價相同，比較就沒有意義），
  # 此時整張表省略，前後文字仍然成立。
  def render_table(spec)
    return if spec.blank?

    div(class: "overflow-x-auto") do
      table(class: "w-full text-[20px] bg-white rounded-lg border border-slate-300") do
        thead do
          tr(class: "border-b border-slate-300 text-left text-slate-500") do
            Array(spec[:headers]).each { |h| th(class: "py-2 px-3 font-medium") { plain(h) } }
          end
        end
        tbody do
          Array(spec[:rows]).each_with_index do |row, i|
            tr(class: i.odd? ? "bg-slate-50" : "") do
              Array(row).each { |cell| td(class: cell_class(cell)) { plain(cell) } }
            end
          end
        end
      end
    end
  end

  # 報酬依正負上色。判斷依據是字串首字元而不是欄位位置：教學表格的欄數
  # 日後可能增減，綁死「第三欄」等於埋一個改欄位就默默失效的規則。
  #
  # 「盈利完全達標卻虧損」正是第五節要證明的事，一整排同色會讓那幾列
  # 看起來跟獲利列沒兩樣。
  #
  # 顏色一律走 ApplicationComponent#change_color（綠漲紅跌），與 FairPrice
  # 其餘頁面同一套——同一個站裡兩種漲跌配色比沒有顏色更糟。
  def cell_class(cell)
    base = "py-2 px-3 tabular-nums"
    sign = cell.to_s[0]
    return base unless [ "+", "-" ].include?(sign)

    "#{base} font-medium #{change_color(sign == '+' ? 1 : -1)}"
  end

  def render_callout(text)
    div(class: "rounded-lg border border-amber-300 bg-amber-50 px-4 py-3") do
      p(class: "text-[20px] text-amber-900 leading-[1.6]") { plain(text) }
    end
  end
end
