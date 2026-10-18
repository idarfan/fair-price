# frozen_string_literal: true

module HallOfFame
  # P5 持股表：最新一份年報（annual／amendment）的資產列與 §4 三欄佔比。
  # 兩種檢視：全部資產（all）與僅有價證券（securities，ticker 非空），分母各自重算。
  class HoldingsView
    ANNUAL_TYPES = %w[annual amendment].freeze

    def initialize(official)
      @official = official
    end

    def as_json(*)
      filing = latest_annual
      return nil unless filing

      holdings = filing.holdings.order(:id).to_a
      {
        doc_id: filing.doc_id, year: filing.year, filing_date: filing.filing_date,
        as_of: filing.year && "#{filing.year}/12/31",
        parse_status: filing.parse_status, parse_error: filing.parse_error, pdf_url: filing.pdf_url,
        views: {
          all:        view(holdings, filing),
          securities: view(holdings.select { |h| h.ticker.present? }, filing)
        }
      }
    end

    private

    def latest_annual
      @official.filings.where(filing_type: ANNUAL_TYPES).where.not(parse_status: %w[pending failed])
               .order(year: :desc, filing_date: :desc, id: :desc).first
    end

    def view(holdings, filing)
      reasons  = holdings.to_h { |h| [ h.id, RowCheck.exclusion_reason(asset_name: h.asset_name, owner: h.owner, min: h.value_min, label: h.value_label) ] }
      eligible = holdings.reject { |h| reasons[h.id] }
      result   = ShareCalculator.call(eligible.map { |h| { key: h.id, min: h.value_min, max: h.value_max } })
      rows     = holdings.map { |h| row(h, result.for(h.id), reasons[h.id], filing) }
      { rows: sort(rows), upper_note: result.upper_note, excluded_count: holdings.size - eligible.size }
    end

    def row(holding, share, excluded_reason, filing)
      {
        id: holding.id, asset_name: holding.asset_name, ticker: holding.ticker, owner: holding.owner,
        value_label: holding.value_label, value_min: holding.value_min, value_max: holding.value_max,
        unbounded: holding.value_max.nil? && holding.value_min.present?,
        estimated: share&.estimated, lower: share&.lower, upper: share&.upper,
        excluded_reason: excluded_reason, needs_review: filing.parse_status == "needs_review"
      }
    end

    # 依估算佔比降冪；不列入佔比的列排在最後，保持原順序。
    def sort(rows)
      rows.each_with_index.sort_by { |r, i| [ r[:estimated] ? 0 : 1, -(r[:estimated] || 0), i ] }.map(&:first)
    end
  end
end
