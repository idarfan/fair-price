# frozen_string_literal: true

# 顯示格式集中在這裡，兩個 calculator 與 view 共用同一套規則。
#
# 負號一律 ASCII hyphen-minus（U+002D）。規格禁用 U+2212：圖表匯出成 PNG 之後
# 沒有人會回頭核對字元碼，而 U+2212 在部分字體下會與減號寬度不同，直接毀掉
# 數字欄位的對齊。
module PriceIn
  module Formatter
    module_function

    # EPS／股價：2 位小數，前綴 $
    def money(value)
      return "—" if value.nil?

      format("$%.2f", value.to_f)
    end

    # 報酬率：1 位小數 + %，正數強制 +
    def percent(ratio)
      return "—" if ratio.nil?

      format("%+.1f%%", ratio.to_f * 100)
    end

    # 隱含本益比：1 位小數 + 「倍」
    def multiple(value)
      return "—" if value.nil?

      format("%.1f 倍", value.to_f)
    end
  end
end
