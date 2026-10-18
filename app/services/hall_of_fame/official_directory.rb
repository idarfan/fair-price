# frozen_string_literal: true

module HallOfFame
  # P5 人物卡列表與單一人物詳細資料（API 與頁面共用，避免兩套序列化）。
  class OfficialDirectory
    SYNC_KINDS = SyncRun::KINDS

    def cards(category)
      officials = Official.where(category: category, active: true).order(:id).to_a
      stats = Filing.where(official_id: officials.map(&:id)).group(:official_id)
                    .pluck(:official_id, Arel.sql("MAX(filing_date)"),
                           Arel.sql("COUNT(*) FILTER (WHERE filing_type = 'ptr')"),
                           Arel.sql("COUNT(*) FILTER (WHERE parse_status = 'needs_review')"))
                    .to_h { |id, latest, ptr, review| [ id, { latest_filing_date: latest, ptr_count: ptr, needs_review_count: review } ] }
      officials.map do |o|
        { slug: o.slug, display_name: o.display_name, district: o.district, title: o.title,
          latest_filing_date: nil, ptr_count: 0, needs_review_count: 0 }.merge(stats.fetch(o.id, {}))
      end
    end

    def profile(official)
      {
        official: { slug: official.slug, display_name: official.display_name, district: official.district, title: official.title },
        holdings: HoldingsView.new(official).as_json,
        trades: TradesView.new(official).as_json,
        synced_at: synced_at(official.source)
      }
    end

    private

    # 「資料更新時間」取各 kind 最近一次結束的 run（P3b 審查質詢 2：不得用 option_details.updated_at）。
    def synced_at(source)
      SYNC_KINDS.index_with do |kind|
        SyncRun.where(source: source, kind: kind).where.not(finished_at: nil).maximum(:finished_at)
      end
    end
  end
end
