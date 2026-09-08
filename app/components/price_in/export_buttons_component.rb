# frozen_string_literal: true

# 匯出按鈕（PNG／PDF）。
#
# data-export-exclude 讓 html-to-image 的 filter 把按鈕本身排除在輸出之外——
# 不過在本工具其實用不到那個 filter：匯出的是另一個離屏容器，按鈕根本不在裡面。
# 保留這個屬性是為了與 LEAPS 的匯出慣例一致，日後若改走截圖路線不會漏掉。
class PriceIn::ExportButtonsComponent < ApplicationComponent
  LOCALE = PriceIn::FieldHelpCardComponent::LOCALE

  def initialize(key:)
    @key = key
  end

  def view_template
    # tour_step 14 是導覽最後一步。錨點要到 S8 做出匯出按鈕才存在，
    # 在那之前導覽會自動略過該步（不中斷、不報錯）。
    div(class: "flex items-center gap-2 shrink-0",
        data: { export_exclude: "true", tour_step: (14 if @key == "chart_a") }.compact) do
      export_button("png")
      export_button("pdf")
    end
  end

  private

  def export_button(kind)
    button(
      type: "button",
      id: "price-in-export-#{@key}-#{kind}",
      data: { price_in_export: kind, export_key: @key },
      class: "px-3 py-1.5 rounded-lg bg-white/15 border border-white/30 text-[16px] " \
             "text-white hover:bg-white/25 transition-colors"
    ) { plain(I18n.t("price_in.export.#{kind}", locale: LOCALE)) }
  end
end
