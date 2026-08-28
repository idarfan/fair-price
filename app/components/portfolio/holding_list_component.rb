# frozen_string_literal: true

class Portfolio::HoldingListComponent < ApplicationComponent
  HEADERS = [
    { label: "",         align: "left",  width: "w-6" },
    { label: "代號",     align: "left"  },
    { label: "股數",     align: "right" },
    { label: "現價",     align: "right" },
    { label: "變更$",    align: "right" },
    { label: "變更%",    align: "right" },
    { label: "市值",     align: "right" },
    { label: "單位成本", align: "right" },
    { label: "成本",     align: "right" },
    { label: "盈虧$",    align: "right" },
    { label: "盈虧%",    align: "right" },
    { label: "賣出價",   align: "right" },
    { label: "目標獲利", align: "right" },
    { label: "",         align: "right" }
  ].freeze

  def initialize(holdings:, quotes: {})
    @holdings = holdings
    @quotes   = quotes
  end

  def view_template
    div(class: "space-y-5") do
      render_header
      render_add_form
      render_ocr_import
      if @holdings.any?
        render_table
      else
        render_empty_state
      end
    end
    render Shared::OwnershipPanelComponent.new
    render_script
  end

  private

  def render_header
    div do
      h1(class: "text-xl font-bold text-gray-900") do
        span(class: "mr-2") { plain("📁") }
        plain("個人持股追蹤")
      end
      p(class: "text-sm text-gray-400 mt-0.5") { plain("追蹤持倉市值、損益與目標出場價") }
    end
  end

  def render_add_form
    div(class: "bg-white rounded-xl border border-gray-100 shadow-sm p-5") do
      h2(class: "text-sm font-semibold text-gray-600 mb-3") { plain("新增持股") }
      form(action: "/portfolio", method: "post",
           class: "flex flex-wrap gap-2 items-end") do
        input(type: "hidden", name: "authenticity_token",
              value: helpers.form_authenticity_token)

        [
          { id: "pf_symbol",    name: "portfolio[symbol]",     label: "股票代號",    type: "text",   placeholder: "AAPL",   extra: { required: true, maxlength: 10 }, cls: "w-24 font-mono uppercase" },
          { id: "pf_shares",    name: "portfolio[shares]",     label: "股數",        type: "number", placeholder: "10",     extra: { required: true, step: "0.00001", min: "0.00001" }, cls: "w-28" },
          { id: "pf_unit_cost", name: "portfolio[unit_cost]",  label: "單位成本",    type: "number", placeholder: "150.00", extra: { required: true, step: "0.00001", min: "0.00001" }, cls: "w-32" },
          { id: "pf_sell",      name: "portfolio[sell_price]", label: "賣出價(選填)", type: "number", placeholder: "—",      extra: { step: "0.01", min: "0" }, cls: "w-28" }
        ].each do |f|
          div(class: "flex flex-col gap-1") do
            label(class: "text-xs text-gray-400", for: f[:id]) { plain(f[:label]) }
            input(
              type:        f[:type],
              id:          f[:id],
              name:        f[:name],
              placeholder: f[:placeholder],
              class:       "#{f[:cls]} px-2 py-1.5 text-sm border border-gray-200 rounded-lg " \
                           "focus:outline-none focus:ring-2 focus:ring-blue-300",
              **f[:extra]
            )
          end
        end

        button(type: "submit",
               class: "px-4 py-1.5 bg-blue-600 text-white text-sm font-medium rounded-lg " \
                      "hover:bg-blue-700 transition-colors") { plain("新增") }
      end
    end
  end

  def render_ocr_import
    div(class: "bg-white rounded-xl border border-gray-100 shadow-sm p-5") do
      h2(class: "text-sm font-semibold text-gray-600 mb-1") do
        span(class: "mr-1") { plain("🖼️") }
        plain("圖片匯入（OCR）")
      end
      p(class: "text-xs text-gray-400 mb-3") { plain("上傳持股截圖，自動辨識代號、股數、單位成本並覆寫現有資料") }

      form(action: "/portfolio/ocr_import", method: "post",
           enctype: "multipart/form-data", class: "flex flex-wrap items-end gap-3") do
        input(type: "hidden", name: "authenticity_token", value: helpers.form_authenticity_token)

        div(class: "flex flex-col gap-1") do
          label(class: "text-xs text-gray-400", for: "ocr_image") { plain("選擇圖片（PNG / JPG）") }
          input(
            type: "file", id: "ocr_image", name: "image",
            accept: "image/png,image/jpeg,image/jpg,image/webp", required: true,
            class: "text-sm text-gray-600 file:mr-3 file:py-1.5 file:px-3 file:rounded-lg " \
                   "file:border-0 file:text-xs file:font-medium file:bg-blue-50 " \
                   "file:text-blue-700 hover:file:bg-blue-100 cursor-pointer"
          )
        end

        button(type: "submit", id: "ocr-submit-btn",
               class: "px-4 py-1.5 bg-indigo-600 text-white text-sm font-medium rounded-lg " \
                      "hover:bg-indigo-700 transition-colors") { plain("辨識並匯入") }

        span(id: "ocr-loading", class: "hidden text-xs text-indigo-500 animate-pulse") do
          plain("🔍 辨識中，請稍候…")
        end
      end

      div(class: "mt-2 flex items-center gap-1.5 text-xs text-amber-600 bg-amber-50 px-3 py-2 rounded-lg") do
        plain("⚠️ 匯入將覆寫現有所有持股資料，請確認後再操作。")
      end
    end
  end

  def render_table
    div(class: "bg-white rounded-xl border border-gray-100 shadow-sm overflow-hidden") do
      div(class: "overflow-x-auto") do
        table(class: "w-full text-sm") do
          render_thead
          tbody(id: "sortable-portfolio") do
            @holdings.each do |holding|
              render Portfolio::HoldingRowComponent.new(
                holding: holding,
                quote:   @quotes[holding.symbol]
              )
            end
          end
        end
      end
    end
  end

  def render_thead
    thead(class: "bg-gray-50 border-b border-gray-100") do
      tr do
        HEADERS.each do |h|
          align_class = h[:align] == "right" ? "text-right" : "text-left"
          th(class: "px-2 py-2 #{align_class} text-xs font-semibold text-gray-400 uppercase " \
                    "tracking-wide whitespace-nowrap #{h[:width]}") do
            plain(h[:label])
          end
        end
      end
    end
  end

  def render_empty_state
    div(class: "bg-white rounded-xl border border-gray-100 shadow-sm px-5 py-12 text-center") do
      span(class: "text-3xl block mb-3") { plain("📁") }
      p(class: "text-gray-400 text-sm") { plain("尚無持股，請使用上方表單新增") }
    end
  end

  # JavaScript 已搬到 app/frontend/behaviors/portfolioHoldings.js（稽核 H-3）。
  # entrypoints/behaviors.ts 會依 data-behavior 動態載入該模組。
  def render_script
    div(data: { behavior: "portfolio-holdings" })
  end
end
