# frozen_string_literal: true

# 教學說明的數字全部由使用者當前填的欄位算出。
#
# 為什麼不寫死範例：第一版拿 NOK 的固定數字當教材，等於在一個「拿你自己的
# 數字演一次」的工具裡放一份別人的作業。抽象規則看得懂不代表套得到自己的
# 情境，而 price in 的誤判恰恰都發生在「套到自己身上」那一步。
# 同樣的理由，LogicExampleBuilder 早就是這樣做的。
#
# 算式與圖表共用同一組 calculator，不另寫一份：教學裡的數字若跟圖上的對不起來，
# 使用者第一個懷疑的會是圖，而不是教學。
#
# 資料齊不齊決定哪幾節顯示得出來（ready 的三個旗標）：
#   ttm    → 按過「帶入現價」，才知道目前實際賺多少
#   band   → 填了 EPS 預測區間，才算得出隱含倍數
#   anchor → 有一個「未來 EPS」的錨（圖 B 的 EPS，或預測區間中點），才畫得出兩張表
# 缺的那幾節顯示 fallback 提示，不顯示半套數字——半套數字比沒有更容易誤導。
module PriceIn
  class TutorialExample
    def self.call(...) = new(...).call

    def initialize(form:)
      @form = form
    end

    def call
      { ready: ready, vars: vars, tables: { multiple: multiple_table, entry: entry_table } }
    end

    private

    def ready
      { ttm: ttm?, band: band?, anchor: anchor_eps.present? }
    end

    def ttm?  = eps_ttm.present? && eps_ttm.positive?
    def band? = band_low.present? && band_high.present? && band_low.positive? && band_high.positive?

    def price      = @form.price.to_f
    def eps_ttm    = @form.eps_ttm_hint
    def band_low   = @form.eps_band_low
    def band_high  = @form.eps_band_high

    # 未來 EPS 的錨。優先取圖 B 那一格——那是使用者明確表態的假設；
    # 沒填才退回預測區間中點，因為兩張表都需要「固定一個盈利」才成立。
    def anchor_eps
      return @anchor_eps if defined?(@anchor_eps)

      @anchor_eps =
        if @form.eps.present? && @form.eps.to_f.positive? then @form.eps.to_f
        elsif band?                                       then (band_low + band_high) / 2
        end
    end

    def anchor_source
      @form.eps.present? && @form.eps.to_f.positive? ? "圖 B 的未來 EPS" : "預測區間中點"
    end

    # 圖 B 的倍數，因為兩張表演的正是圖 B 在做的事。排序後取中位數那一檔
    # 當「進場價」表的固定倍數：取端點等於替使用者選了最樂觀或最悲觀的情境。
    def multiples = @multiples ||= Array(@form.chart_b_multiples).map(&:to_f).select(&:positive?).sort

    def mid_multiple = multiples[multiples.length / 2]

    def entry_prices
      [ @form.entry_a_price, @form.entry_b_price ].compact.map(&:to_f).select(&:positive?).uniq
    end

    # ── 表一：固定 EPS，只改倍數 ────────────────────────────
    #
    # 買入價固定用圖 A 的買入基準（＝股價），與圖 A 問的「這個價格要求賺多少」
    # 同一個立足點。這張表要證明的是：盈利完全達標，倍數不同，報酬可以從
    # 虧損跨到翻倍。
    def multiple_table
      return nil if anchor_eps.nil? || multiples.empty?

      entry = @form.entry_a_price.to_f
      return nil unless entry.positive?

      rows = multiples.map do |m|
        target = EntryReturnCalculator.target_price(anchor_eps, m)
        [ Kernel.format("%g 倍", m), Formatter.money(target),
          Formatter.percent(EntryReturnCalculator.total_return(target, entry)) ]
      end
      { headers: [ "假設倍數", "目標價", "報酬" ], rows: rows }
    end

    # ── 表二：固定 EPS 與倍數，只改買入價 ──────────────────
    def entry_table
      return nil if anchor_eps.nil? || mid_multiple.nil? || entry_prices.length < 2

      target = EntryReturnCalculator.target_price(anchor_eps, mid_multiple)
      rows   = entry_prices.sort.reverse.map do |entry|
        [ entry_label(entry), Formatter.money(target),
          Formatter.percent(EntryReturnCalculator.total_return(target, entry)) ]
      end
      { headers: [ "買入價", "目標價", "報酬" ], rows: rows }
    end

    def entry_label(entry)
      suffix = entry == @form.entry_a_price.to_f ? "（買入基準）" : ""
      "#{Formatter.money(entry)}#{suffix}"
    end

    # ── 文案代入值 ─────────────────────────────────────────

    def vars
      {
        ticker:        @form.ticker.presence || "這檔",
        price:         Formatter.money(price),
        band_year:     @form.fiscal_year_label.presence || "該年度",
        anchor_year:   @form.chart_b_fiscal_year_label.presence || "該年度",
        anchor_source: anchor_source
      }.merge(ttm_vars).merge(band_vars).merge(anchor_vars).merge(table_vars)
    end

    def ttm_vars
      return {} unless ttm?

      { eps_ttm: Formatter.money(eps_ttm), implied_ttm: Formatter.multiple(price / eps_ttm) }
    end

    # 高 EPS 對應低倍數，所以隱含倍數的低端用 band_high 去除。寫反會得到
    # 上下顛倒但兩端都「看起來合理」的區間，肉眼掃過去不會停。
    def band_vars
      return {} unless band?

      {
        band_low:    Formatter.money(band_low),
        band_high:   Formatter.money(band_high),
        fwd_low:     Formatter.multiple(price / band_high),
        fwd_high:    Formatter.multiple(price / band_low),
        band_spread: Kernel.format("%.0f%%", (band_high - band_low) / (band_high + band_low) * 100)
      }
    end

    def anchor_vars
      return {} if anchor_eps.nil?

      out = { anchor_eps: Formatter.money(anchor_eps), anchor_mult: Formatter.multiple(price / anchor_eps) }
      return out unless ttm?

      out.merge(
        growth_pct:      Kernel.format("%+.0f%%", (anchor_eps / eps_ttm - 1) * 100),
        ttm_mult_target: Formatter.money(anchor_eps * (price / eps_ttm))
      )
    end

    def table_vars
      out = {}
      if (t = multiple_table)
        out[:mult_worst] = t[:rows].first.last
        out[:mult_best]  = t[:rows].last.last
      end
      if mid_multiple && anchor_eps
        out[:mid_multiple] = Kernel.format("%g 倍", mid_multiple)
        out[:mid_target]   = Formatter.money(EntryReturnCalculator.target_price(anchor_eps, mid_multiple))
      end
      out
    end
  end
end
