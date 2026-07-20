# frozen_string_literal: true

# bcvs.md §快取機制：PostgreSQL 為快取層（非 bpus 用的 Rails.cache），
# TTL 30 分鐘；查詢未過期直接回快取、不觸發 sidecar；過期則由呼叫端重抓後
# 呼叫這裡的 upsert_* 方法 UPSERT 更新既有列，不新增重複列（唯一索引為
# 最後防線）。bid=0/OI=0 剔除固定在寫入 chain 之前於此完成（Ruby 業務規則層，
# 沿用 bpus「Python 不做業務篩選」的分工）。
class BcvsCacheService
  class << self
    def fresh_expirations?(symbol)
      BcvsExpirationSnapshot.for_symbol(symbol).fresh.exists?
    end

    def read_expirations(symbol)
      snapshot = BcvsExpirationSnapshot.for_symbol(symbol).first
      return nil unless snapshot

      {
        expirations:      snapshot.expirations,
        underlying_price: snapshot.underlying_price&.to_f,
        summary:          summary_of(snapshot)
      }
    end

    # bcvs.md §功能流程 步驟1（v4）：標的摘要五值（現價與漲跌／Latest Earnings／
    # IV ATM／HV／IV Rank）隨到期日清單同快取，皆為選配（DOM 抓不到就是 nil，
    # 不得造值）。
    def upsert_expirations!(symbol, expirations:, underlying_price:, price_change: nil,
                             iv_atm: nil, hv: nil, iv_rank: nil, latest_earnings: nil)
      snapshot = BcvsExpirationSnapshot.find_or_initialize_by(symbol: symbol.upcase)
      snapshot.update!(
        expirations:       Array(expirations),
        underlying_price:  underlying_price,
        price_change:      price_change,
        iv_atm:            iv_atm,
        hv:                hv,
        iv_rank:           iv_rank,
        latest_earnings:   latest_earnings,
        scraped_at:        Time.current
      )
      snapshot
    end

    def fresh_chain?(symbol, expiration)
      BcvsChainSnapshot.for_symbol_and_expiration(symbol, expiration).fresh.exists?
    end

    def read_chain(symbol, expiration)
      snapshot = BcvsChainSnapshot.for_symbol_and_expiration(symbol, expiration).first
      return nil unless snapshot

      {
        strikes:           snapshot.strikes,
        underlying_price:  snapshot.underlying_price&.to_f
      }
    end

    def upsert_chain!(symbol, expiration, strikes:, underlying_price:)
      filtered = filter_quotable(strikes)

      snapshot = BcvsChainSnapshot.find_or_initialize_by(symbol: symbol.upcase, expiration: expiration)
      snapshot.update!(
        strikes:           filtered,
        underlying_price:  underlying_price,
        scraped_at:        Time.current
      )
      snapshot
    end

    private

    def summary_of(snapshot)
      {
        price_change:    snapshot.price_change&.to_f,
        iv_atm:          snapshot.iv_atm&.to_f,
        hv:              snapshot.hv&.to_f,
        iv_rank:         snapshot.iv_rank&.to_f,
        latest_earnings: snapshot.latest_earnings
      }
    end

    # bid 與 ask 皆為 null/0 的 strike 剔除（bcvs.md §3.2 沿用 bpus 分工）。
    def filter_quotable(strikes)
      Array(strikes).select do |row|
        bid = row["bid"] || row[:bid]
        ask = row["ask"] || row[:ask]
        bid.to_f.positive? || ask.to_f.positive?
      end
    end
  end
end
