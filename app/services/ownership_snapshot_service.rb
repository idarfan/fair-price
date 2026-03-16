# frozen_string_literal: true

class OwnershipSnapshotService
  def save_snapshot(ticker, data)
    ticker  = ticker.upcase
    summary = data[:summary] || {}

    ActiveRecord::Base.transaction do
      snapshot = OwnershipSnapshot.find_or_initialize_by(
        ticker:  ticker,
        quarter: current_quarter
      )
      snapshot.update!(
        snapshot_date:     Date.current,
        institutional_pct: summary[:institutions_pct],
        insider_pct:       summary[:insiders_pct],
        institution_count: summary[:institutions_count]
      )
      snapshot.ownership_holders.destroy_all
      (data[:top_holders] || []).each do |holder|
        snapshot.ownership_holders.create!(
          name:         holder[:name],
          pct:          holder[:pct_held],
          market_value: holder[:value],
          filing_date:  holder[:report_date],
          pct_change:   holder[:pct_change]
        )
      end
      snapshot
    end
  end

  def load_history(ticker, since: 1.year.ago.to_date)
    OwnershipSnapshot
      .for_ticker(ticker)
      .where("snapshot_date >= ?", since)
      .includes(:ownership_holders)
  end

  def previous_snapshot(ticker, before_snapshot: nil)
    snapshots = OwnershipSnapshot.for_ticker(ticker)
    snapshots = snapshots.where("snapshot_date < ?", before_snapshot.snapshot_date) if before_snapshot
    snapshots.includes(:ownership_holders).last
  end

  def current_quarter
    q = (Date.current.month - 1) / 3 + 1
    "#{Date.current.year}-Q#{q}"
  end
end
