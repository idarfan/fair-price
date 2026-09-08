# frozen_string_literal: true

# 匯出用的離屏卡片（規格 §S8.1）。
#
# **匯出與畫面完全脫鉤**：不截取畫面上那張卡片，而是另建一個離屏容器渲染
# 匯出版本。理由是畫面寬度會隨視窗變動，直接截圖等於讓成品尺寸取決於使用者
# 的瀏覽器大小；同一組參數在不同機器上匯出必須得到同一張圖，否則存檔前後
# 無法比對。
#
# 容器固定 960×540 CSS px，以 pixelRatio 2 捕捉 → 恆為 1920×1080。
# 為什麼不直接開 1920 寬：容器若真的用 1920，20px 的字只佔畫面寬度的百分之一，
# 成品圖上小到看不清。在 960 寬排版、再以 2 倍捕捉，字才有正確的相對大小。
#
# 用 position:absolute + left:-99999px 移出視野，**不可用 display:none**
# ——html-to-image 量不到尺寸，會產出空白圖。
class PriceIn::ExportCardComponent < ApplicationComponent
  LOCALE = PriceIn::FieldHelpCardComponent::LOCALE

  WIDTH  = 960
  HEIGHT = 540

  # key: "chart_a" / "chart_b"
  def initialize(key:, form:, title:, subtitle:, source_canvas_id:, band: nil, eps_banner: nil)
    @key      = key
    @form     = form
    @title    = title
    @subtitle = subtitle
    @canvas   = source_canvas_id
    @band     = band
    @banner   = eps_banner
  end

  def view_template
    div(
      id: "price-in-export-#{@key}",
      class: "pi-export-stage",
      data: { export_card: @key, source_canvas: @canvas }
    ) do
      div(id: "price-in-export-#{@key}-fit", class: "pi-export-fit") do
        header_row
        titles
        banner if @banner.present?
        chart_slot
        highlight
        footer_row
      end
    end
  end

  private

  def header_row
    div(class: "pi-export-head") do
      span(class: "pi-export-brand") { plain(t_export(:brand, ticker: @form.ticker)) }
      span(class: "pi-export-badge") { plain(t_export(:badge)) }
    end
  end

  def titles
    h2(class: "pi-export-title") { plain(@title) }
    p(class: "pi-export-subtitle") { plain(@subtitle) }
  end

  def banner
    p(class: "pi-export-banner") { plain(@banner) }
  end

  # 圖表以 <img> 承載：匯出時把畫面上那個 canvas 轉成 dataURL 填進來。
  # 在離屏容器裡再開一個 Chart.js 實例會讓同一份資料有兩個繪製路徑，
  # 兩邊字級或版面一走鐘就會產出與畫面不一致的成品。
  def chart_slot
    div(class: "pi-export-chart") do
      img(id: "price-in-export-#{@key}-img", alt: @title, class: "pi-export-img")
    end
  end

  def highlight
    p(class: "pi-export-highlight") { plain(t_export(:"#{@key}_highlight")) }
  end

  def footer_row
    div(class: "pi-export-foot") do
      span { plain(t_export(:signature)) }
      span(id: "price-in-export-#{@key}-basis") { plain(price_basis) }
    end
  end

  def price_basis
    return t_export(:manual_price) if @form.price_as_of.blank?

    t_export(:quote_basis, time: @form.price_as_of.strftime("%Y-%m-%d %H:%M"))
  end

  def t_export(key, **) = I18n.t("price_in.export.#{key}", locale: LOCALE, **)
end
