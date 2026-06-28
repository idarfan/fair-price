# frozen_string_literal: true

# Prepares data for the Options Flow independent panel on the LEAPS page.
#
# Reads today's OptionsFlowTrade rows for the symbol, computes directional
# premium summaries, surfaces large orders, and cross-references trades against
# the top-N LEAPS candidates by (strike, expiration_date).
#
# This panel is purely informational — it NEVER modifies ranking order.
# The UI must display its title as "情緒參考，非排序依據".
class LeapsOptionsFlowPanelService
  TOP_N_DEFAULT   = 5
  LARGE_ORDER_TOP = 20

  def initialize(symbol, ranked_candidates, top_n: TOP_N_DEFAULT)
    @symbol            = symbol.upcase
    @ranked_candidates = ranked_candidates
    @top_n             = top_n
  end

  def call
    date   = Date.current
    trades = OptionsFlowTrade.for_symbol_date(@symbol, date).to_a
    return { status: :no_data, date: date } if trades.empty?

    trade_hashes = trades.map(&:attributes)
    aggregate    = OptionsFlowClassifierService.aggregate(trade_hashes)

    {
      status:             :ok,
      date:               date,
      call_premium_total: premium_total(trades, "Call"),
      put_premium_total:  premium_total(trades, "Put"),
      large_orders:       large_orders(trades),
      highlighted_trades: cross_reference(trades),
      aggregate:          aggregate
    }
  end

  private

  def premium_total(trades, type)
    trades.select { |t| t.option_type == type }.sum { |t| t.premium.to_i }
  end

  def large_orders(trades)
    trades
      .sort_by { |t| -t.premium.to_i }
      .first(LARGE_ORDER_TOP)
      .map { |t| trade_summary(t) }
  end

  # Returns trades that match the top-N ranked candidates on (strike, expiration_date).
  # Grouped by candidate rank so the UI can show context like
  # "今天在排行第1的 $10 Strike / 2027-01-15 附近有一筆大額買權買入".
  def cross_reference(trades)
    top = @ranked_candidates.first(@top_n)
    top.filter_map.with_index(1) do |candidate, rank|
      matched = trades.select { |t| matches?(t, candidate) }
      next if matched.empty?

      {
        rank:             rank,
        candidate_strike: candidate[:strike],
        candidate_expiry: candidate[:expiration_date],
        trades:           matched.sort_by { |t| -t.premium.to_i }.map { |t| trade_summary(t) }
      }
    end
  end

  def matches?(trade, candidate)
    trade.strike.to_f      == candidate[:strike].to_f &&
      trade.expires_at.to_date == candidate[:expiration_date].to_date
  end

  def trade_summary(trade)
    {
      option_type:     trade.option_type,
      strike:          trade.strike,
      expires_at:      trade.expires_at,
      trade_price:     trade.trade_price,
      size:            trade.size,
      side:            trade.side,
      premium:         trade.premium,
      open_close:      trade.open_close,
      trade_condition: trade.trade_condition,
      large_premium:   trade.large_premium,
      delta:           trade.delta,
      dte:             trade.dte,
      trade_time:      trade.trade_time
    }
  end
end
