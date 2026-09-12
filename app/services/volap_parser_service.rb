# frozen_string_literal: true

# 把 VolapSnapshot 的原始分箱轉成畫面要用的形狀。
#
# **不重算 POC 與 Value Area**——那兩個是 Barchart 自己算的，存在 snapshot 裡，
# 這裡只轉格式並額外標出 HVN／LVN。同一個數字兩套算法是規格明文禁止的 bug 溫床
# （見 leaps_option_chain_snapshot.rb 對 derived_values 的同一則告誡）。
class VolapParserService
  # 相對於「量最大的箱（POC）」的比例門檻。
  #
  # ⚠️ 這兩個數字是**拿實際資料校準過的**，不是憑感覺訂的（feedback_boolean_sort_key
  # 的教訓：門檻沒對過實際分佈就會整排 tie 或全空）。
  #
  # SHOP 日線 1 年實測的占比分佈（24 箱，由大到小）：
  #   100.0 / 69.0 / 64.4 / 63.3 / 61.3 ‖ 49.4 / 45.4 / 43.0 / 42.5 / …（中位數 33.7）
  # 61.3 與 49.4 之間有明顯斷層，取中點 0.55——
  # 最初設 0.70，結果一個 HVN 都選不到。
  #
  # 換 NOK 驗證過不是只對 SHOP 有效（避免單一標的過擬合）：
  #   NOK 占比 100.0 / 75.9 / 62.3 / 59.0 / 55.2 ‖ 53.8 / 45.9 / …
  #   0.55 在兩檔都選出 4 個 HVN 箱，數量級一致。
  HVN_RATIO = 0.55

  # ≤ 20% → 低量節點（沒人想在此成交，價格容易快速穿越）。
  #
  # **只在 Value Area 之內才算 LVN**：價格區間的頭尾本來就沒什麼成交量，
  # 那是「價格很少走到那裡」而不是「走到了但沒人接」，標成 LVN 沒有解讀價值。
  # SHOP 實測：不加這個限制會選出 94–101 與 167–182 兩段尾巴，
  # 加了之後只剩 134.42–138.10 這個真正夾在量堆之間的低量口袋。
  LVN_RATIO = 0.20

  Bin = Data.define(
    :index, :low, :high, :mid, :up, :down, :total, :pct_of_max,
    :is_value, :is_poc, :is_hvn, :is_lvn
  )

  def initialize(snapshot)
    @snapshot = snapshot
  end

  # 回傳 Bin 陣列，**由低價到高價**（index 遞增）。畫面要由高到低就自己 reverse，
  # 不要在這裡先轉——低到高才對得上 snapshot 的 index 語意。
  def bins
    @bins ||= build_bins
  end

  private def build_bins
    return [] if @snapshot.nil?

    rows = Array(@snapshot.bars)
    return [] if rows.empty?

    totals = rows.map { |b| volume_of(b) }
    max = totals.max
    # 整段期間完全沒有成交量（極冷門標的或抓到壞資料）：不要除以零，
    # 也不要回傳一堆 0% 的箱假裝有資料，直接回空讓上層降級。
    return [] if max.nil? || max.zero?

    rows.each_with_index.map do |row, i|
      low, high = @snapshot.bin_range(i)
      total = totals[i]
      ratio = total.to_f / max
      Bin.new(
        index: i,
        low: low.to_f.round(4), high: high.to_f.round(4),
        mid: ((low + high) / 2).to_f.round(4),
        up: row["up"].to_i, down: row["down"].to_i, total: total,
        pct_of_max: (ratio * 100).round(2),
        is_value: !!row["is_value"],
        is_poc: i == @snapshot.poc_index,
        # POC 本身不重複標成 HVN——它在 POI 清單裡已經是獨立、更精確的一項。
        is_hvn: i != @snapshot.poc_index && ratio >= HVN_RATIO,
        is_lvn: !!row["is_value"] && ratio <= LVN_RATIO
      )
    end
  end

  # 相鄰的同類節點合併成價區（例如 126–132 的 HVN 帶）。
  # 逐箱各標一個標籤會讓 POI 清單被同一個現象洗版。
  # kind: :hvn 或 :lvn
  def merged_zones(kind)
    flag = kind == :hvn ? :is_hvn : :is_lvn

    bins.chunk { |b| b.public_send(flag) }
        .select { |flagged, _| flagged }
        .map do |_, group|
          { kind: kind,
            low: group.first.low, high: group.last.high,
            bins: group.map(&:index),
            pct_of_max: group.map(&:pct_of_max).max }
        end
  end

  def poc_bin = bins.find(&:is_poc)

  # jsonb 讀回來是字串 key。上漲量與下跌量分開存（Up/Down 配色要用），
  # 判斷節點強弱時看的是兩者相加的總量。
  private def volume_of(row)
    row["up"].to_i + row["down"].to_i
  end

  # Value Area 的價格上下緣（Barchart 標好的 isValue 箱的外緣）。
  # isValue 的箱在 Barchart 的定義下是連續的，但這裡用 min/max 而不是
  # first/last，萬一哪天不連續也不會給出比實際窄的區間。
  def value_area
    va = bins.select(&:is_value)
    return nil if va.empty?
    { low: va.map(&:low).min, high: va.map(&:high).max }
  end
end
