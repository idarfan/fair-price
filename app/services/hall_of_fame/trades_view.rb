# frozen_string_literal: true

module HallOfFame
  # P5 交易表：近 12 個月的 PTR 交易列、期權欄位，以及 §4 交易佔比（買進、賣出分開算）。
  class TradesView
    WINDOW = 12.months
    PURCHASE_TYPES = %w[P].freeze
    SALE_TYPES     = %w[S S_partial].freeze
    SOURCE_LABELS  = { "stated_contracts" => "申報", "barchart_dom" => "Barchart 當日收盤", "bs_model" => "模型估算" }.freeze

    def initialize(official, today: Time.zone.today)
      @official = official
      @cutoff   = today - WINDOW
    end

    def as_json(*)
      trades = recent_trades
      reasons = trades.to_h { |t| [ t.id, RowCheck.exclusion_reason(asset_name: t.asset_name, owner: t.owner, min: t.amount_min, label: t.amount_label) ] }
      {
        since: @cutoff,
        rows: trades.map { |t| row(t, reasons[t.id]) },
        shares: { purchase: shares(trades, reasons, PURCHASE_TYPES), sale: shares(trades, reasons, SALE_TYPES) }
      }
    end

    private

    # tx_date 解析不出（needs_review）的列以申報日判斷是否在期間內，不靜默丟掉。
    def recent_trades
      Trade.joins(:filing).includes(:filing, :option_detail)
           .where(hof_filings: { official_id: @official.id, filing_type: "ptr" })
           .where("hof_transactions.tx_date >= :d OR (hof_transactions.tx_date IS NULL AND hof_filings.filing_date >= :d)", d: @cutoff)
           .order(Arel.sql("hof_transactions.tx_date DESC NULLS LAST"), :id).to_a
    end

    def row(trade, excluded_reason)
      filing = trade.filing
      {
        id: trade.id, tx_date: trade.tx_date, notified_date: trade.notified_date, asset_name: trade.asset_name,
        ticker: trade.ticker, owner: trade.owner, tx_type: trade.tx_type, amount_label: trade.amount_label,
        amount_min: trade.amount_min, amount_max: trade.amount_max, doc_id: filing.doc_id, pdf_url: filing.pdf_url,
        needs_review: filing.parse_status == "needs_review", excluded_reason: excluded_reason,
        option: trade.option_detail && option(trade.option_detail)
      }
    end

    def option(detail)
      {
        right: detail.option_right, strike: detail.strike&.to_f, expiration: detail.expiration,
        contracts: contracts_label(detail), premium: premium_label(detail),
        source: detail.premium_source, source_label: SOURCE_LABELS[detail.premium_source], calc_note: detail.calc_note
      }
    end

    def contracts_label(detail)
      return "申報 #{detail.contracts_stated} 口" if detail.contracts_stated
      return nil unless detail.contracts_est_min

      "約 #{detail.contracts_est_min}～#{detail.contracts_est_max || '∞'} 口"
    end

    def premium_label(detail)
      if detail.premium_implied_min
        max = detail.premium_implied_max ? money(detail.premium_implied_max) : "∞"
        return "#{money(detail.premium_implied_min)}～#{max}"
      end
      detail.premium_ref && money(detail.premium_ref)
    end

    def money(value) = "$#{format('%.2f', value)}"

    # 依 ticker（沒有 ticker 用資產名稱）加總 mid / 同方向總 mid。
    def shares(trades, reasons, types)
      eligible = trades.select { |t| types.include?(t.tx_type) && reasons[t.id].nil? }
      groups   = eligible.group_by { |t| t.ticker.presence || t.asset_name }
      sums     = groups.transform_values { |ts| ts.sum(0r) { |t| ShareCalculator.mid(t.amount_min, t.amount_max) } }
      total    = sums.values.sum(0r)
      sums.sort_by { |_, mid| -mid }.map do |key, mid|
        { key: key, count: groups[key].size, mid: mid.to_f,
          unbounded: groups[key].any? { |t| t.amount_max.nil? },
          estimated: total.zero? ? nil : (mid * 100 / total).to_f.round(4) }
      end
    end
  end
end
