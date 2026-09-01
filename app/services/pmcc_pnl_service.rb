# frozen_string_literal: true

# pmcc-tracker Phase 4：損益帳本。
#
# **已實現只記真實現金流**（已扣手續費），不含任何估算值——帳本的價值在於
# 可稽核，混進估算之後 SUM(realized_pnl) 就跟券商對帳單永遠對不起來。
# 未實現損益另外算、另外顯示，不寫進 pnl_events。
#
# 純計算層：不打 Barchart、不寫 DB。
class PmccPnlService
  CONTRACT_MULTIPLIER = 100

  def self.call(position, long_quote: :lookup)
    new(position, long_quote: long_quote).call
  end

  # ── 各事件類型的已實現金額（供 Phase 5 建立事件時呼叫，公式只寫一次）──────
  #
  # 一律 × 口數 × 100 再扣手續費。原 spec 通篇「每股 ×100」隱含只有 1 口。

  # 到期歸零：收到的權利金全部落袋
  def self.short_expired_pnl(leg, fees: 0)
    net(leg.premium_collected, 0, leg.contracts, fees)
  end

  # 買回平倉（含滾倉時的買回）：收租減買回成本
  def self.short_closed_pnl(leg, close_cost: nil, fees: 0)
    net(leg.premium_collected, close_cost || leg.close_cost || 0, leg.contracts, fees)
  end

  # 被指派：**只記短腳自己的現金流**。長腳因此被行權/平倉，另開一筆
  # long_exercised / long_closed 記它自己的實際成交——把長腳的估算損失
  # 減進這裡會讓已實現帳本不再可稽核（見 pmcc-tracker.md Phase 4 修正）。
  def self.short_assigned_pnl(leg, close_cost: nil, fees: 0)
    net(leg.premium_collected, close_cost || leg.close_cost || 0, leg.contracts, fees)
  end

  # 長腳平倉：賣出價減實付成本
  def self.long_closed_pnl(position, sell_price:, fees: 0)
    net(sell_price, position.long_entry_cost, position.long_contracts, fees)
  end

  def self.net(credit, debit, contracts, fees)
    ((credit.to_f - debit.to_f) * contracts.to_i * CONTRACT_MULTIPLIER - fees.to_f).round(4)
  end
  private_class_method :net

  # ── 部位總覽 ───────────────────────────────────────────────────────────

  def initialize(position, long_quote: :lookup)
    @position   = position
    @long_quote = long_quote
  end

  def call
    {
      realized:            realized,
      unrealized:          unrealized,
      total:               total,
      annualized_return:   annualized_return,
      capital_deployed:    @position.capital_deployed.to_f.round(4),
      holding_days:        holding_days,
      long_leg:            long_leg_summary,
      timeline:            timeline
    }
  end

  private

  # 只加總帳本裡的真實現金流
  def realized
    @realized ||= @position.pnl_events.sum(:realized_pnl).to_f.round(4)
  end

  # 長腳未實現：(市價 − 實付成本) × 口數 × 100。
  # 沒有報價就回 nil，**不要當成 0**——0 會讓「部位總損益」看起來像是
  # 已經確認過沒有浮動，實際上是沒資料。
  def unrealized
    return nil if market_mid.nil?

    ((market_mid - @position.long_entry_cost.to_f) *
      @position.long_contracts * CONTRACT_MULTIPLIER).round(4)
  end

  def total
    unrealized.nil? ? nil : (realized + unrealized).round(4)
  end

  # 年化報酬率。分母用 capital_deployed（實付成本 − 累積已實現）而非原始成本：
  # 滾倉收租會持續降低實際投入，用原始成本會低估報酬。
  # 未實現未知、資本已回收完（≤0）、或天數為 0 時回 nil 而不是硬算。
  def annualized_return
    return nil if total.nil?

    capital = @position.capital_deployed.to_f
    return nil unless capital.positive?

    (total / capital / [ holding_days, 1 ].max * 365).round(6)
  end

  def holding_days
    finish = @position.closed_at&.to_date || Date.current
    (finish - @position.long_entry_date).to_i
  end

  def long_leg_summary
    {
      strike:       @position.long_strike.to_f,
      expiration:   @position.long_expiration,
      contracts:    @position.long_contracts,
      entry_cost:   @position.long_entry_cost.to_f,   # 計算基準
      market_mid:   market_mid,                       # 僅供顯示
      quoted_at:    quote&.scraped_at
    }
  end

  def market_mid
    return @market_mid if defined?(@market_mid)

    @market_mid = quote&.mid&.to_f
  end

  def quote
    return @long_quote unless @long_quote == :lookup

    @quote ||= PmccLegQuote.for_leg(
      @position.ticker, @position.long_expiration, @position.long_strike
    )
  end

  def timeline
    @position.pnl_events.chronological.map do |e|
      {
        event_type:   e.event_type,
        realized_pnl: e.realized_pnl.to_f,
        fees:         e.fees.to_f,
        occurred_at:  e.occurred_at,
        note:         e.note
      }
    end
  end
end
