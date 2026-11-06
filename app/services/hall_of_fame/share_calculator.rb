# frozen_string_literal: true

module HallOfFame
  # §4 佔比計算（唯一定義）：
  # - mid = (min + max) / 2；max 為 NULL 時 mid = min（UI 標「≥」）。
  # - 估算佔比 = mid / Σmid；下限佔比 = min / Σmin；上限佔比 = max / Σmax。
  # - 任一列 max 為 NULL → 上限佔比整欄為 nil，並附原因。
  # 輸入列為 { key:, min:, max: }；min 為 nil 的列不得傳進來（呼叫端先排除，§P5 needs_review 規則）。
  class ShareCalculator
    UPPER_UNAVAILABLE = "有無上限的區間（max 為空），上限佔比無法計算"

    Share  = Data.define(:key, :mid, :estimated, :lower, :upper, :unbounded)
    Result = Data.define(:shares, :upper_note) do
      def for(key) = shares.find { |s| s.key == key }
    end

    def self.call(rows) = new.call(rows)

    def self.mid(min, max) = max.nil? ? min.to_r : Rational(min + max, 2)

    def call(rows)
      unbounded = rows.any? { |r| r[:max].nil? }
      mids      = rows.map { |r| self.class.mid(r[:min], r[:max]) }
      sum_mid   = mids.sum(0r)
      sum_min   = rows.sum(0r) { |r| r[:min] }
      sum_max   = unbounded ? nil : rows.sum(0r) { |r| r[:max] }

      shares = rows.zip(mids).map do |row, mid|
        Share.new(key: row[:key], mid: mid.to_f, unbounded: row[:max].nil?,
                  estimated: pct(mid, sum_mid), lower: pct(row[:min], sum_min),
                  upper: sum_max && pct(row[:max], sum_max))
      end
      Result.new(shares: shares, upper_note: unbounded ? UPPER_UNAVAILABLE : nil)
    end

    private

    # 百分比（0–100），分母為 0 時回 nil（例如全部是 None 的資產）。
    def pct(value, total) = total.zero? ? nil : (value.to_r * 100 / total).to_f.round(4)
  end
end
