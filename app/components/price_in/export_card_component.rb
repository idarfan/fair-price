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
  #
  # table_headers／table_rows／legend／note 讓匯出圖帶上與畫面相同的完整資訊。
  # 只有一張圖的匯出品脫離頁面後就沒有任何線索：看的人不知道那些倍數對應
  # 多少 EPS、綠帶是哪一年、圓點該怎麼讀。
  def initialize(key:, form:, title:, subtitle:, source_canvas_id:,
                 eps_banner: nil, table_headers: [], table_rows: [], legend: [], note: nil)
    @key           = key
    @form          = form
    @title         = title
    @subtitle      = subtitle
    @canvas        = source_canvas_id
    @banner        = eps_banner
    @table_headers = table_headers
    @table_rows    = table_rows
    @legend        = legend
    @note          = note
  end

  def view_template
    # 外層負責「移出視野」，內層才是被拍的元素。
    #
    # 不能把 position:absolute; left:-99999px 放在被拍的元素本身——
    # html-to-image 會把節點的 computed style 一併複製到 clone 上，clone 在
    # SVG foreignObject 裡就被推到 -99999px 外面，拍出來整片空白（PNG 與 PDF
    # 都是，因為 PDF 用的就是 PNG 的點陣圖）。
    #
    # 仍然不可改用 display:none：那樣 html-to-image 量不到尺寸，同樣是空白。
    div(class: "pi-export-offscreen") do
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
          data_table if @table_rows.any?
          legend_row if @legend.any?
          highlight
          footer_row
        end
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

  # 數值表：圖上只看得出長短，實際數字要靠這張表。
  def data_table
    table(class: "pi-export-table") do
      thead do
        tr { @table_headers.each { |h| th { plain(h) } } }
      end
      tbody do
        @table_rows.each do |cells|
          tr { cells.each { |cell| td { plain(cell) } } }
        end
      end
    end
  end

  # 圖例：色塊在匯出圖裡沒辦法用 CSS class 重現顏色對應，改用文字前綴，
  # 例如「灰藍橫條＝…」。顏色本身圖上看得到，缺的是名稱。
  def legend_row
    div(class: "pi-export-legend") do
      @legend.each { |item| span { plain(item) } }
    end
  end

  def highlight
    p(class: "pi-export-highlight") { plain(@note.presence || t_export(:"#{@key}_highlight")) }
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
