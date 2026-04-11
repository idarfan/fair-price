# frozen_string_literal: true

module Api
  module V1
    class OwnershipSnapshotsController < Api::V1::BaseController
      def index
        ticker    = sanitize_ticker(params[:ticker])
        snapshots = service.load_history(ticker, since: range_start)
        latest    = snapshots.last
        previous  = latest ? service.previous_snapshot(ticker, before_snapshot: latest) : nil

        render json: {
          snapshots: snapshots.map { |s| serialize_snapshot(s) },
          previous:  serialize_snapshot(previous)
        }
      end

      def create
        ticker = sanitize_ticker(params[:ticker])
        data   = YahooFinanceService.new.holders(ticker) ||
                 SecEdgarService.new.holders(ticker)

        unless data
          render json: { error: "無法取得 #{ticker} 的持股資料" }, status: :unprocessable_content
          return
        end

        snapshot = service.save_snapshot(ticker, data)
        render json: { snapshot: serialize_snapshot(snapshot) }, status: :created
      end

      private

      def service = OwnershipSnapshotService.new

      def sanitize_ticker(t)
        t.to_s.upcase.gsub(/[^A-Z0-9.\-]/, "").first(10).presence
      end

      # GET /api/v1/ownership_snapshots/WULF?range=1w|1m|90d
      # 支援：1w / 1m / 90d（預設 90d）
      def range_start
        case params[:range]
        when "1w"  then 1.week.ago.to_date
        when "1m"  then 1.month.ago.to_date
        when "90d" then 90.days.ago.to_date
        else            90.days.ago.to_date
        end
      end

      def serialize_snapshot(snapshot)
        return nil unless snapshot

        {
          quarter:           snapshot.quarter,
          date:              snapshot.snapshot_date,
          institutional_pct: snapshot.institutional_pct&.to_f,
          insider_pct:       snapshot.insider_pct&.to_f,
          institution_count: snapshot.institution_count,
          holders:           snapshot.ownership_holders.map { |h|
            {
              name:        h.name,
              pct:         h.pct&.to_f,
              value:       h.market_value,
              filing_date: h.filing_date,
              pct_change:  h.pct_change&.to_f
            }
          }
        }
      end
    end
  end
end
