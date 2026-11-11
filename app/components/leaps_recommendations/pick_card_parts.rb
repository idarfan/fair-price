# frozen_string_literal: true

# 推薦分析兩張卡（💰 最划算、🔓 流動性最佳）共用的版面零件（leaps-best-value-card-style.md S1）。
#
# 兩卡同一結構：膠囊列（膠囊＋次選灰字）→ 說明文字 → 明細格（主推一組、次選一組加標題列）。
# 每個零件帶 data 屬性，方便測試逐一比對兩卡的 class 是否一致。
#
# 使用者裁示（2026-11-11）：
#   1a Mid 由這裡依 LeapsOptionChainSnapshot#mid_price 同一規則自算（兩卡同算法，不改 service）
#   2a 最划算卡膠囊固定綠色（不用 A／B／C 等級上色，避免把「補位」露出來）
module LeapsRecommendations::PickCardParts
  include LeapsRecommendations::SharedConstants

  # 膠囊列：膠囊、（呼叫端額外放的標記）、次選灰字。
  def render_capsule_row(pick, runner_up:, style:)
    div(class: "flex flex-wrap gap-3 mb-3") do
      render_pick_capsule(pick, style)
      yield if block_given?
      if runner_up
        div(class: "text-xs text-gray-400 self-center", data_leaps_runner_up_note: "") do
          plain "次選：#{contract_label(runner_up)}"
        end
      end
    end
  end

  def render_pick_capsule(pick, style)
    div(class: "flex items-center gap-2 px-3 py-1.5 rounded-lg border #{style[:bg]} #{style[:border]}",
        data_leaps_pick_capsule: "") do
      div(class: "w-2 h-2 rounded-full #{style[:dot]}")
      span(class: "text-xs font-semibold #{style[:text]}") { plain contract_label(pick) }
      span(class: "text-xs #{style[:text]} opacity-70") { plain "Delta #{sprintf('%.3f', pick[:delta].to_f)}" }
    end
  end

  def render_pick_reason(text)
    div(class: "text-sm text-gray-700 whitespace-pre-line leading-relaxed", data_leaps_pick_reason: "") { plain text }
  end

  # 明細格：主推一組；次選一組，上方以「次選 $K / 到期日」標題列取代原本的「履約價／到期日」列（patch1）。
  def render_pick_details(pick, runner_up)
    # @container：明細格依「卡片內容寬度」決定欄數，不看視窗寬度（使用者 2026-11-11 裁示，S1 r2 問題 1）。
    div(class: "@container mt-3 pt-3 border-t border-gray-100", data_leaps_pick_details: "") do
      render_metric_list(pick)
      if runner_up
        div(class: "mt-2") do
          div(class: "flex flex-wrap items-center gap-2 mb-1", data_leaps_runner_up_title: "") do
            span(class: "text-xs font-semibold text-gray-800") { plain "次選 #{contract_label(runner_up)}" }
            render_thin_trading_flag(runner_up)
          end
          render_metric_list(runner_up)
        end
      end
    end
  end

  def render_thin_trading_flag(row)
    return unless row[:no_recent_volume_warning]

    span(class: "text-orange-600 text-xs whitespace-nowrap self-center", title: THIN_TRADING_TOOLTIP) { plain THIN_TRADING_LABEL }
  end

  # 欄位與順序固定（規格 S1）：第 1 列 Delta、Mid、Ask、OI、成交量；第 2 列 Spread %、年化時間成本、損益兩平。
  # 最划算卡的列是 LeapsBestValueService 回傳值，指標已算好（不帶 underlying_price）；
  # OI 卡的列是排行候選，沒有指標，用同一支公式補算。
  def render_metric_list(row)
    metrics = row.key?(:annual_cost_pct) ? row : (LeapsBestValueService.metrics(row) || {})
    # 5 欄門檻 @md＝容器 28rem（448px）：每格 (448 − 4×12) ÷ 5 = 80px，最寬標籤「年化時間成本」為 72px。
    dl(class: "grid grid-cols-2 @md:grid-cols-5 gap-x-3 gap-y-1 text-xs", data_leaps_metric_list: "") do
      metric_items(row, metrics).each do |label, value|
        # 標籤在上、數值在下（使用者 2026-11-11 裁示）：兩卡並排時 5 欄每格約 98px，
        # 左右並排會讓「年化時間成本 7.36%」溢出壓到下一格。
        div(class: "flex flex-col min-w-0") do
          dt(class: "text-gray-400 whitespace-nowrap") { plain label }
          dd(class: "text-gray-800 font-mono tabular-nums whitespace-nowrap") { plain value }
        end
      end
    end
  end

  def metric_items(row, metrics)
    [
      [ "Delta",        fmt_decimal(row[:delta], 3) ],
      [ "Mid",          fmt_price(mid_of(row)) ],
      [ "Ask",          fmt_price(row[:ask]) ],
      [ "OI",           fmt_int(row[:open_interest]) ],
      [ "成交量",       fmt_int(row[:volume]) ],
      [ "Spread %",     fmt_cost_pct(metrics[:spread_pct]) ],
      [ "年化時間成本", fmt_cost_pct(metrics[:annual_cost_pct]) ],
      [ "損益兩平",     fmt_cost_pct(metrics[:breakeven_pct]) ]
    ]
  end

  # 與 LeapsOptionChainSnapshot#mid_price 同一規則：兩邊都有取平均，缺一邊取另一邊，都缺為 nil。
  def mid_of(row)
    bid = row[:bid]
    ask = row[:ask]
    return nil if bid.nil? && ask.nil?
    return ask.to_f if bid.nil?
    return bid.to_f if ask.nil?

    (bid.to_f + ask.to_f) / 2.0
  end

  def contract_label(row) = "#{sprintf('$%.2f', row[:strike].to_f)} / #{row[:expiration_date]}"

  # 已經是百分比數值（7.36 → "7.36%"），跟既有 fmt_pct（小數 ×100）不同，所以另開一支。
  def fmt_cost_pct(value) = value.nil? ? "—" : sprintf("%.2f%%", value)
end
