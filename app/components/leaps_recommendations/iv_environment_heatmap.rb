# frozen_string_literal: true

# IV 曲面熱圖（leaps-iv-environment.md P5 內容 4）：列＝到期日（DTE 由小到大）、欄＝moneyness 0.60…1.25。
# 每格取 |moneyness − 欄值| ≤ 0.025 中最接近的點；色階依 LEAPS 列的 IV 最小→最大線性對應（P5.1）。
#
# 背景色不能寫 style 屬性（CSP 擋 inline style），改由 data-accent-bg 帶 #rrggbb，
# 由 shared/dataStyles.ts 經 CSSOM 套上（專案既有做法）。
module LeapsRecommendations::IvEnvironmentHeatmap
  HEAT_COLUMNS   = (0..13).map { |i| (0.60 + i * 0.05).round(2) }.freeze
  HEAT_TOLERANCE = 0.025
  HEAT_LOW       = "#eff6ff" # 表內最低 IV
  HEAT_HIGH      = "#1d4ed8" # 表內最高 IV
  ATM_COLUMN     = 1.00
  LEAPS_MIN_DTE  = LeapsRankingService::MIN_DTE # 與爬蟲 LEAPS_MIN_DTE、推薦近天期下限同一個值（364）
  # 背景深到這個比例以上，格內文字改白色才看得清楚
  DARK_TEXT_FROM = 0.55

  # P5.1（使用者裁示）：LEAPS 列（DTE ≥ LEAPS_MIN_DTE）在上、決定色階；PMCC 短天期列排在下方，灰底不上色。
  # 短天期 IV 常高達 90%，若一起算色階，LEAPS 列會全擠在最淺的顏色裡看不出差異。
  def render_heatmap
    rows = heatmap_rows
    return p(class: "text-sm text-gray-500") { plain "尚無曲面資料" } if rows.empty?

    leaps, short = rows.partition { |r| r[:dte] >= LEAPS_MIN_DTE }
    lo, hi = leaps.flat_map { |r| r[:cells].compact }.minmax
    div(class: "overflow-x-auto") do
      table(class: "w-full text-xs border-collapse", data: { ivenv_heatmap: "" }) do
        render_heatmap_head
        tbody do
          leaps.each { |row| render_heatmap_row(row, "leaps") { |iv, col| render_heatmap_cell(iv, col, lo, hi) } }
          render_short_divider if short.any?
          short.each { |row| render_heatmap_row(row, "short") { |iv, col| render_short_cell(iv, col) } }
        end
      end
    end
  end

  private

  def render_heatmap_head
    thead do
      tr(data: { tip_key: "ivenv_moneyness" }, class: "text-gray-500 cursor-help") do
        th(class: "px-2 py-1 text-left font-medium whitespace-nowrap") { plain "到期日 ＼ K÷S" }
        HEAT_COLUMNS.each do |col|
          th(class: "px-1 py-1 text-center font-medium #{atm_col_class(col)}",
             data: { ivenv_col: sprintf("%.2f", col) }) { plain sprintf("%.2f", col) }
        end
      end
    end
  end

  def render_heatmap_row(row, kind)
    tr(data: { ivenv_row: kind }) do
      th(class: "px-2 py-1 text-left font-medium text-gray-700 whitespace-nowrap") do
        plain "#{row[:expiration]}（#{row[:dte]} 天）"
      end
      row[:cells].each_with_index { |iv, i| yield(iv, HEAT_COLUMNS[i]) }
    end
  end

  def render_short_divider
    tr(data: { ivenv_row: "divider" }) do
      td(colspan: HEAT_COLUMNS.size + 1, class: "px-2 pt-3 pb-1 text-xs font-medium text-gray-500") do
        plain "PMCC 短天期（參考，不上色）"
      end
    end
  end

  def render_short_cell(iv, col)
    base = "px-1 py-1 text-center tabular-nums bg-gray-100 #{atm_col_class(col)}"
    return td(class: "#{base} text-gray-300") { plain "—" } if iv.nil?

    td(class: "#{base} text-gray-600") { plain sprintf("%.1f%%", iv * 100) }
  end

  def render_heatmap_cell(iv, col, lo, hi)
    base = "px-1 py-1 text-center tabular-nums #{atm_col_class(col)}"
    return td(class: "#{base} text-gray-300") { plain "—" } if iv.nil? || lo.nil?

    t = hi == lo ? 0.0 : (iv - lo) / (hi - lo)
    text = t >= DARK_TEXT_FROM ? "text-white" : "text-gray-800"
    td(class: "#{base} #{text}", data: { accent_bg: heat_color(t) }) { plain sprintf("%.1f%%", iv * 100) }
  end

  def atm_col_class(col)
    col == ATM_COLUMN ? "ivenv-atm-col" : ""
  end

  # [{ expiration:, dte:, cells: [iv 或 nil] × 14 }]，依 DTE 由小到大
  def heatmap_rows
    Array(@env[:surface]).group_by { |pt| [ pt[:dte], pt[:expiration] ] }.sort_by { |(dte, _), _| dte }
                         .map do |(dte, exp), pts|
      { expiration: exp, dte: dte, cells: HEAT_COLUMNS.map { |col| nearest_iv(pts, col) } }
    end
  end

  def nearest_iv(points, col)
    near = points.select { |pt| pt[:call_iv] && (pt[:moneyness] - col).abs <= HEAT_TOLERANCE + 1e-9 }
    near.min_by { |pt| (pt[:moneyness] - col).abs }&.dig(:call_iv)
  end

  def heat_color(t)
    from = hex_rgb(HEAT_LOW)
    to   = hex_rgb(HEAT_HIGH)
    "#" + from.zip(to).map { |a, b| sprintf("%02x", (a + (b - a) * t).round) }.join
  end

  def hex_rgb(hex)
    hex.delete("#").scan(/../).map { |h| h.to_i(16) }
  end
end
