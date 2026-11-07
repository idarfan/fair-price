# frozen_string_literal: true

# /leaps 的 IV 環境區塊（leaps-iv-environment.md P5），放在「推薦分析」上方。
#
# 資料一律來自 LeapsIvEnvironmentService#call 的回傳值（controller 傳進來），這裡不查 DB。
# 外殼沿用價格情境卡的 pc-card 寫法（<details>/<summary>），但依規格**預設收合、不記憶展開狀態**。
# 名詞說明走既有 tooltips.js：元素帶 data-tip-key，文案在 IV_ENV_EXPLAIN。
class LeapsRecommendations::IvEnvironmentSection < ApplicationComponent
  include LeapsRecommendations::IvEnvironmentHeatmap

  CARD_CLASS   = "bg-white rounded-2xl border border-gray-200 shadow-sm flex flex-col pc-card"
  FULL_HISTORY = LeapsIvEnvironmentService::MAX_HISTORY
  NO_DATA_TEXT = "尚無 IV 資料，請按查詢"
  ERROR_TEXT   = "IV 環境資料讀取失敗，請重新整理頁面；若持續發生請查看伺服器 log"
  DASH         = "—"
  TAIPEI       = "Asia/Taipei"
  IV_DROP_PTS  = 5 # tooltip「IV 每下降 5 點」

  def initialize(symbol:, env:, near_pick: nil)
    @symbol    = symbol
    @env       = env || {}
    @near_pick = near_pick
  end

  def view_template
    details(id: "leaps-iv-environment", class: CARD_CLASS, data: { behavior: "leaps-iv-environment" }) do
      render_summary
      div(class: "px-5 pb-5 space-y-5") do
        if error?
          p(class: "text-sm text-red-600") { plain ERROR_TEXT }
        elsif no_data?
          p(class: "text-sm text-gray-500") { plain NO_DATA_TEXT }
        else
          render_body
        end
      end
    end
  end

  private

  def error? = @env[:status] == :error
  def no_data? = @env[:status].nil? || @env[:status] == :no_data
  def accumulating? = @env[:status] == :accumulating
  def barchart = @env[:barchart] || {}

  # ── summary ────────────────────────────────────────────────────────────────
  def render_summary
    summary(class: "pc-summary flex items-start justify-between gap-3 px-5 pt-5 pb-4 " \
                   "cursor-pointer rounded-2xl select-none hover:bg-gray-50 transition-colors") do
      div(class: "min-w-0") do
        div(class: "flex items-center gap-1.5") do
          h3(class: "pc-title text-xl font-extrabold tracking-wide") { plain "IV 環境 · #{@symbol}" }
          span(class: "text-sm text-gray-400 cursor-help", data: { tip_key: "ivenv_overview" }) { plain "ⓘ" }
        end
        p(class: "pc-sub text-xs mt-1") { plain "LEAPS 天期 IV Rank ＋ Barchart 參考" }
      end
      div(class: "flex items-center gap-3 shrink-0 mt-1") do
        span(class: "hidden text-xs font-medium text-amber-700 bg-amber-50 border border-amber-200 rounded px-1.5 py-0.5",
             data: { ivenv_updating: "" }) { plain "更新中" }
        span(class: "text-sm text-gray-600 tabular-nums") { plain summary_text }
        span(class: "pc-chevron", aria_hidden: "true")
      end
    end
  end

  def summary_text
    return "讀取失敗" if error?
    return NO_DATA_TEXT if no_data?

    text = "Barchart IV Rank #{fmt_int(barchart[:iv_rank])} · ATM IV（540 天）#{fmt_iv(@env[:cm540])}"
    accumulating? ? "#{text} · 累積中 #{history_ratio}" : text
  end

  # ── 內容 ───────────────────────────────────────────────────────────────────
  def render_body
    render_badges
    div(class: "grid grid-cols-1 lg:grid-cols-2 gap-5") do
      render_chart_box("ivenv_bc_trend", "Barchart IV Rank 走勢", "Barchart 30 天天期", "barchart", barchart_points)
      render_chart_box("ivenv_term", "ATM IV 期限結構", "虛線＝540 天", "term", term_points)
    end
    div do
      render_box_title("ivenv_surface", "IV 曲面", "格內為 Call IV；橘框＝最接近現價（1.00）的一欄")
      render_heatmap
    end
    render_meta
  end

  def render_badges
    div(class: "grid grid-cols-1 md:grid-cols-2 gap-4") do
      div(class: "space-y-2") do
        p(class: "text-xs font-medium text-gray-500") { plain "LEAPS 天期（FairPrice 自算）" }
        div(class: "flex flex-wrap gap-2") do
          badge("ivenv_leaps_rank", "LEAPS IV Rank（540 天）", leaps_value(@env[:rank]), lines: vega_lines)
          badge("ivenv_leaps_pct", "IV Percentile", leaps_value(@env[:percentile]))
          badge("ivenv_cm540", "ATM IV（540 天）", fmt_iv(@env[:cm540]))
        end
        p(class: "text-xs text-gray-500 cursor-help w-fit", data: { tip_key: "ivenv_accumulating" }) do
          plain accumulating? ? "資料累積中 #{history_ratio} 天" : "歷史資料 #{history_ratio} 天"
        end
      end
      div(class: "space-y-2") do
        p(class: "text-xs font-medium text-gray-500") { plain "Barchart 參考（天期依頁面定義）" }
        div(class: "flex flex-wrap gap-2") do
          badge("ivenv_bc_rank", "Barchart IV Rank", fmt_rank(barchart[:iv_rank]))
          badge("ivenv_bc_pctl", "IV Pctl", fmt_rank(barchart[:iv_pctl]))
          badge("ivenv_bc_iv", "Imp Vol", fmt_iv(barchart[:imp_vol]))
          badge("ivenv_bc_hv", barchart[:hv_label].presence || "HV", fmt_iv(barchart[:hv]))
        end
      end
    end
  end

  def badge(key, label, value, lines: nil)
    sep  = label.end_with?("）") ? "" : " " # 全形括號後不再加空白
    data = { tip_key: key, tip_value: value == DASH ? nil : "#{label}#{sep}#{value}", tip_lines: lines }.compact
    div(class: "rounded-lg border border-gray-200 bg-gray-50 px-3 py-2 cursor-help", data: data) do
      p(class: "text-xs text-gray-500 whitespace-nowrap") { plain label }
      p(class: "text-lg font-bold text-gray-900 tabular-nums", data: { ivenv_value: "" }) { plain value }
    end
  end

  # 累積中時 Rank／Percentile 還沒有值：顯示「累積中」，不顯示 0 或空白
  def leaps_value(value)
    return "累積中" if accumulating?

    fmt_int(value)
  end

  def render_chart_box(key, title, note, kind, points)
    div do
      render_box_title(key, title, note)
      div(class: "h-56") do
        canvas(data: { ivenv_chart: kind, ivenv_points: points.to_json })
      end
    end
  end

  def render_box_title(key, title, note)
    div(class: "flex items-baseline gap-2 mb-2") do
      h4(class: "text-sm font-bold text-gray-800 cursor-help", data: { tip_key: key }) { plain title }
      span(class: "text-xs text-gray-500") { plain note }
    end
  end

  def render_meta
    div(class: "text-xs text-gray-500 flex flex-wrap gap-x-4 gap-y-1 border-t border-gray-100 pt-3 cursor-help",
        data: { tip_key: "ivenv_meta" }) do
      span { plain "as_of_date #{@env[:as_of_date] || DASH}（美東）" }
      span { plain "captured_at #{fmt_taipei(@env[:captured_at])}（台北）" }
      span { plain "source #{@env[:source] || DASH}" }
      if @env[:source_url].present?
        a(href: @env[:source_url], target: "_blank", rel: "noopener noreferrer",
          class: "text-blue-600 hover:underline break-all") { plain @env[:source_url] }
      end
    end
  end

  # ── 圖表資料（交給 leapsIvEnvironment.ts 畫）────────────────────────────────
  def term_points
    Array(@env[:term_structure]).filter_map do |pt|
      { x: pt[:dte], y: (pt[:atm_iv] * 100).round(2) } if pt[:atm_iv]
    end
  end

  def barchart_points
    rows = Array(barchart[:history])
    { labels: rows.map { |r| r[:trade_date].to_s }, rank: rows.map { |r| r[:iv_rank] },
      price: rows.map { |r| r[:last_price] } }
  end

  # ── tooltip 計算句（data-tip-lines）─────────────────────────────────────────
  def vega_lines
    vega = @near_pick && @near_pick[:vega]
    return nil if vega.nil?

    loss = (vega.to_f * IV_DROP_PTS * 100).round
    [
      "以推薦近天期 #{fmt_number(@near_pick[:strike])} / #{@near_pick[:expiration_date]}（Vega #{sprintf('%.4f', vega)}）計算",
      "IV 每下降 #{IV_DROP_PTS} 點，每口約損失 $#{loss.to_s.reverse.scan(/\d{1,3}/).join(',').reverse}"
    ].to_json
  end

  # ── 格式 ───────────────────────────────────────────────────────────────────
  def history_ratio = "#{@env[:history_count].to_i}/#{FULL_HISTORY}"
  def fmt_iv(v) = v.nil? ? DASH : sprintf("%.1f%%", v.to_f * 100)
  def fmt_int(v) = v.nil? ? DASH : v.to_f.round.to_s
  def fmt_rank(v) = v.nil? ? DASH : sprintf("%.2f", v.to_f).sub(/\.?0+\z/, "")

  def fmt_number(v)
    f = v.to_f
    f == f.to_i ? f.to_i.to_s : f.to_s
  end

  def fmt_taipei(time)
    time ? time.in_time_zone(TAIPEI).strftime("%Y-%m-%d %H:%M") : DASH
  end
end
