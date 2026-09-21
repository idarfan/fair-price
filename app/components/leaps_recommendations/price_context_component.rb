# frozen_string_literal: true

# LEAPS 頁的三個價格情境 widget：POI / 52 週區間 / 當日區間。
#
# 獨立成一個 Phlex component（而不是併進 PageComponent 的 module）是因為
# controller 的 price_context action 要能單獨把它 render 成 HTML 字串回給前端輪詢。
#
# ⚠️ **這裡一律不用 inline style**。CSP 的 style-src 沒有 'unsafe-inline'
# （config/initializers/content_security_policy.rb），HTML 的 style 屬性會被
# 瀏覽器整個丟掉——顏色、長條寬度全部消失，而且不會有任何錯誤訊息。
#   靜態顏色 → app/assets/tailwind/application.css 的 .pc-* class
#   動態數值 → data-bar-pct / data-marker-pct，由 shared/dataStyles.ts 走 CSSOM 套上
# 這是專案既有的做法（見 bullCallSpreads.ts / ivAnalysis.ts），不要另創一套。
class LeapsRecommendations::PriceContextComponent < ApplicationComponent
  CARD_CLASS = "bg-white rounded-2xl border border-gray-200 shadow-sm flex flex-col"

  # empty_message：沒資料的那張卡顯示什麼。預設「載入中」只適用於
  # **還會再有東西進來**的情況（頁面初次渲染、或輪詢回 pending）。
  # 一旦抓取走到終局（no_volap_plot／session 過期／CDP 離線），controller 會
  # 傳「暫無資料」把它換掉——否則畫面會停在一個永遠不會結束的「載入中…」，
  # 系統其實早就放棄了（2026-09-21 NOK 實際症狀）。
  def initialize(payload:, empty_message: "價格情境資料載入中…")
    @payload = payload || {}
    @empty_message = empty_message
  end

  def view_template
    div(id: "leaps-price-context-cards",
        class: "grid grid-cols-1 md:grid-cols-[1.35fr_1fr_1fr] gap-4 items-stretch") do
      render_poi_card
      render_range_card(
        key: "week52", title: "52 週區間", subtitle: "近 52 週最高 / 最低",
        caption: "52WK RANGE", data: @payload[:week52], extra: week52_extra
      )
      # 副標帶上實際的 K 棒日期，不要寫死「今日」——盤中最新一根可能還是昨天的，
      # 寫「今日」會讓使用者以為現價和這個區間是同一個時間點的東西。
      render_range_card(
        key: "day", title: "當日區間", subtitle: day_subtitle,
        caption: "DAY'S RANGE", data: @payload[:day_range], extra: day_extra
      )
    end
  end

  private

  # --- 卡片外殼（可收摺）----------------------------------------------------
  # 用 <details>/<summary> 而不是 JS 開關：Phlex 2.x 封鎖所有 on* 事件屬性
  # （feedback_phlex_unsafe_attrs）。收摺狀態的記憶在 leapsPriceContext.ts。
  def card(key:, title:, subtitle:, anchor_id: nil, &block)
    details(id: anchor_id, class: "#{CARD_CLASS} pc-card", open: true, data: { pc_key: key }) do
      summary(class: "pc-summary flex items-start justify-between gap-3 px-5 pt-5 pb-4 " \
                     "cursor-pointer rounded-2xl select-none hover:bg-gray-50 transition-colors") do
        div(class: "min-w-0") do
          h3(class: "pc-title text-xl font-extrabold tracking-wide") { plain title }
          p(class: "pc-sub text-xs mt-1") { plain subtitle }
        end
        span(class: "pc-chevron shrink-0 mt-2", aria_hidden: "true")
      end
      div(class: "px-5 pb-5 flex flex-col flex-1", &block)
    end
  end

  # --- POI --------------------------------------------------------------------
  def render_poi_card
    poi = @payload[:poi]
    return render_empty_card("POI", "Volume Profile 關注點") if poi.blank?

    subtitle = "Volume Profile（Barchart VOLAP）· #{poi[:period_label]} · " \
               "#{poi[:level_size]} 箱 · #{poi[:volume_mode]}"

    card(key: "poi", anchor_id: "leaps-poi-card",
         title: "POI · #{@payload[:symbol]}", subtitle: subtitle) do
      div(id: "leaps-poi-rows", class: "flex flex-col gap-1.5 mt-1") do
        # 由高價到低價，跟看盤軟體的價格軸一致。
        poi[:bins].reverse_each { |bin| render_poi_row(bin, poi) }
      end
      render_poi_legend
    end
  end

  def render_poi_row(bin, poi)
    labels = Array(poi[:labels_by_bin][bin.index])
    is_now = bin.index == poi[:current_bin_index]

    div(id: (is_now ? "leaps-poi-now" : nil),
        class: [ "relative flex items-center gap-2 h-[17px] rounded-md",
                 (bin.is_value ? "pc-row-va" : nil) ].compact.join(" ")) do
      render_now_line if is_now
      # 現價膠囊與 POI 標籤**共用同一欄且並排**，不是疊在一起。
      # 一開始把膠囊做成 absolute left-0，結果現價那列的標籤被整個蓋掉
      # （實測畫面上只剩「…99–132.60」）。
      div(class: "shrink-0 w-[186px] flex items-center justify-end gap-1.5 relative z-20") do
        if is_now
          span(class: "pc-now-pill text-[11px] font-bold px-2 py-0.5 rounded-full whitespace-nowrap") do
            plain "現價 #{fmt_price(@payload[:current_price])}"
          end
        end
        # 每個標籤各自一個 span 並帶 data-tip-key：滑過看名詞解釋、點擊看
        # driver.js 聚光說明（引擎在 app/assets/javascripts/leaps_recommendations/tooltips.js）。
        # 一整列合併成一個 span 的話，HVN 與履約價擠在同一箱時就只能共用一份解釋。
        # 刻意**不加 title 屬性**：瀏覽器的原生提示會跟自訂 tooltip 疊在一起，
        # 兩層黑框互相遮擋很難看（使用者實測截圖）。完整數值改由 data-tip-value
        # 傳進 tooltip 內容，由 tooltips.js 顯示在解釋文字的最上面。
        labels.each_with_index do |item, i|
          span(class: "pc-dot text-[10px]") { plain "/" } if i.positive?
          span(class: "pc-label pc-term text-[10.5px] font-bold truncate",
               data: { tip_key: item[:tip], tip_value: item[:label] }.compact) do
            plain item[:label]
          end
        end
      end
      div(class: "flex-1 min-w-0 flex justify-end relative z-10") { render_volume_bar(bin) }
      div(class: "#{is_now ? 'pc-price-now' : 'pc-price'} shrink-0 w-14 text-right " \
                 "text-xs font-semibold tabular-nums relative z-10") { plain fmt_price(bin.high) }
    end
  end

  # 綠＝上漲 K 貢獻的量、紅＝下跌 K 貢獻的量（Barchart VOLAP 的 Up/Down 模式），
  # **不是**「支撐/壓力」。兩段並排，整條寬度代表該價位的總量占比。
  def render_volume_bar(bin)
    return if bin.total.zero?

    up_pct = (bin.up.to_f / bin.total * 100).round(2)
    div(class: "pc-bar", data: { bar_pct: bin.pct_of_max }) do
      div(class: "pc-bar-up",   data: { bar_pct: up_pct })
      div(class: "pc-bar-down", data: { bar_pct: (100 - up_pct).round(2) })
    end
  end

  # 橫貫長條區的紫線。起點對齊標籤欄的右緣（w-[186px] + gap-2 = 194px）。
  def render_now_line
    div(class: "pc-now-line absolute left-[194px] right-14 top-1/2 h-0.5 rounded-sm " \
               "-translate-y-1/2 z-0")
  end

  def render_poi_legend
    div(id: "leaps-poi-legend",
        class: "mt-4 pt-3 border-t border-gray-100 flex flex-wrap items-center gap-x-4 gap-y-2 " \
               "text-[11px] text-gray-600") do
      span(class: "pc-term", data: { tip_key: "poi_updown" }) do
        span(class: "pc-sw pc-sw-up"); plain "上漲量 Up"
      end
      span(class: "pc-term", data: { tip_key: "poi_updown" }) do
        span(class: "pc-sw pc-sw-down"); plain "下跌量 Down"
      end
      span(class: "pc-term", data: { tip_key: "poi_now" }) do
        span(class: "pc-sw-now"); plain "現價"
      end
      span(class: "pc-term", data: { tip_key: "poi_value_area" }) do
        span(class: "pc-sw pc-sw-va"); plain "Value Area 70%"
      end
      # 「POI 到底是什麼」本身也要能問——它不是圖上任何一條，是整張卡的主題。
      span(class: "pc-term pc-label font-bold", data: { tip_key: "poi_overview" }) do
        plain "❓ 什麼是 POI"
      end
    end
  end

  # --- 區間條（52 週 / 當日共用）---------------------------------------------
  def render_range_card(key:, title:, subtitle:, caption:, data:, extra:)
    return render_empty_card(title, subtitle) if data.blank?

    card(key: key, anchor_id: "leaps-#{key}-card", title: title, subtitle: subtitle) do
      div(class: "pc-price flex justify-between items-baseline text-lg font-bold tabular-nums mt-1") do
        span { plain fmt_price(data[:low]) }
        span { plain fmt_price(data[:high]) }
      end
      render_range_track(data)
      p(class: "pc-caption mt-2.5 text-center text-[11px] font-semibold") { plain caption }
      render_range_note(data)
      div(class: "flex-1 min-h-[8px]")
      render_kv_rows(extra) if extra.present?
    end
  end

  def render_range_track(data)
    pos = data[:position_pct]
    div(class: "pc-track relative mt-2.5 h-3.5 rounded-full") do
      if pos
        div(class: "pc-fill absolute left-0 top-0 bottom-0 rounded-full", data: { bar_pct: pos })
        # marker_offset 9 = 三角形半寬，讓尖端對準百分比位置。
        div(class: "pc-cursor absolute -top-[13px]",
            data: { marker_pct: pos, marker_offset: 9 })
      end
    end
  end

  def render_range_note(data)
    if data[:price_outside_range]
      # 不畫游標、也不假裝位置正常。現價與區間來自不同時間點時，
      # 誠實講出來比畫一個看起來合理的假位置有用。
      p(class: "mt-3 text-xs text-amber-700 bg-amber-50 border border-amber-200 rounded-lg px-2.5 py-1.5") do
        plain "現價 #{fmt_price(@payload[:current_price])} 落在此區間之外，可能來自較早的快照"
      end
      return
    end

    p(class: "pc-note mt-3 text-[13px]") do
      plain "現價位於區間 "
      span(class: "pc-pct-up font-bold") { plain "#{data[:position_pct]}%" }
      span(class: "pc-dot mx-1.5") { plain "·" }
      plain "距高點 "
      span(class: "pc-pct-down font-bold") { plain "#{data[:from_high_pct]}%" }
    end
  end

  def render_kv_rows(rows)
    div(class: "mt-3.5 pt-3.5 border-t border-gray-100 flex flex-col gap-2") do
      rows.each do |label, value|
        div(class: "flex justify-between text-xs text-gray-500") do
          span { plain label }
          span(class: "pc-price font-semibold tabular-nums") { plain value }
        end
      end
    end
  end

  def week52_extra
    w = @payload[:week52]
    return nil if w.blank?
    { "52 週高" => fmt_price(w[:high]), "52 週低" => fmt_price(w[:low]),
      "距低點" => w[:from_low_pct] ? "+#{w[:from_low_pct]}%" : "—" }
  end

  def day_subtitle
    date = @payload.dig(:day_range, :bar_date)
    date ? "#{date.strftime('%Y-%m-%d')} 最高 / 最低" : "最新交易日最高 / 最低"
  end

  def day_extra
    d = @payload[:day_range]
    return nil if d.blank?
    { "開盤" => fmt_price(d[:open]),
      "前收" => d[:prev_close] ? fmt_price(d[:prev_close]) : "—",
      "當日振幅" => d[:amplitude_pct] ? "#{d[:amplitude_pct]}%" : "—" }
  end

  def render_empty_card(title, subtitle)
    card(key: title, title: title, subtitle: subtitle) do
      p(class: "text-sm text-gray-400 py-6 text-center") { plain @empty_message }
    end
  end

  def fmt_price(value)
    return "—" if value.nil?
    sprintf("%.2f", value.to_f)
  end
end
