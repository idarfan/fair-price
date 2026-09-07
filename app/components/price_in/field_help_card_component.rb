# frozen_string_literal: true

# 欄位用途說明卡。每個輸入群組上方一張，回答「要填什麼／為什麼要填／怎麼用／注意」。
#
# **預設完全不顯示**（2026-09-07 依使用者要求，先改收摺、再改為隱藏）。
# 只收摺仍然留下八條橫條把輸入框往下推；真正在填表的人不需要它們佔位。
# 由頁首的「輸入導覽」開關切換：關＝整批不渲染在畫面上，開＝出現（仍是收摺狀態）。
#
# 用原生 <details>/<summary>，與 §S4 的收摺清單同一套機制，不引入 accordion 套件。
#
# 卡身內容以「有標頭列的表格」呈現，不是段落散文（規格 §S4）——散文會讓人整段跳過。
# 文案一律來自 config/locales/price_in.zh-TW.yml，元件內不硬編任何句子。
# 全站 default_locale 是 :en，因此查詢時明確指定 locale，不動全站設定。
class PriceIn::FieldHelpCardComponent < ApplicationComponent
  LOCALE = :"zh-TW"

  # 色系語意（規格 §S4）：綠＝公式/基準、橙＝對照/規範、黃＝決策/警示、紅＝關鍵警語。
  TONES = {
    "green"  => { band: "bg-emerald-800", body: "bg-emerald-50/50",
                  border: "border-emerald-300", label: "text-emerald-900" },
    "orange" => { band: "bg-orange-800",  body: "bg-orange-50/50",
                  border: "border-orange-300", label: "text-orange-900" },
    "yellow" => { band: "bg-amber-700",   body: "bg-amber-50/50",
                  border: "border-amber-300", label: "text-amber-900" },
    "red"    => { band: "bg-rose-800",    body: "bg-rose-50/50",
                  border: "border-rose-300", label: "text-rose-900" }
  }.freeze

  def initialize(key:, ticker:)
    @key    = key
    @ticker = ticker
    @card   = I18n.t("price_in.cards.#{key}", locale: LOCALE)
    @tone   = TONES.fetch(@card[:tone], TONES["green"])
  end

  def view_template(&block)
    details(
      class: "pi-card pi-help rounded-xl border #{@tone[:border]} overflow-hidden mb-3"
    ) do
      summary_band
      div(class: "px-4 py-3 #{@tone[:body]} border-t #{@tone[:border]}") do
        rows_table
        block&.call
      end
    end
  end

  private

  def summary_band
    summary(class: "min-h-[44px] flex items-center justify-between gap-3 px-4 py-2 #{@tone[:band]} cursor-pointer select-none") do
      p(class: "text-[20px] font-medium text-white") { plain(@card[:title]) }
      span(class: "pi-chevron text-white/70 text-[16px] shrink-0") { plain("▾") }
    end
  end

  def rows_table
    table(class: "w-full text-[20px] border-collapse") do
      thead do
        tr(class: "border-b #{@tone[:border]} text-left") do
          th(class: "py-2 pr-4 font-medium #{@tone[:label]} w-[10rem] align-top") { plain("項目") }
          th(class: "py-2 font-medium #{@tone[:label]}") { plain("說明") }
        end
      end
      tbody do
        Array(@card[:rows]).each { |row| render_row(row) }
      end
    end
  end

  def render_row(row)
    tr(class: "border-b border-black/5 hover:bg-black/[0.03]") do
      td(class: "py-2 pr-4 align-top #{@tone[:label]} font-medium") { plain(row[:label]) }
      td(class: "py-2 align-top text-gray-700") do
        # 句號斷行：locale 已經一句一個元素，這裡每句一個 block，line-height 1.6。
        Array(row[:body]).each do |sentence|
          div(class: "leading-[1.6]") { plain(sentence) }
        end
      end
    end
  end
end
