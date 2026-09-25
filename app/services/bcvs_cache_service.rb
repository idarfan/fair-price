# frozen_string_literal: true

# bcvs.md §快取機制：PostgreSQL 為快取層（非 bpus 用的 Rails.cache），
# TTL 30 分鐘；查詢未過期直接回快取、不觸發 sidecar；過期則由呼叫端重抓後
# 呼叫這裡的 upsert_* 方法 UPSERT 更新既有列，不新增重複列（唯一索引為
# 最後防線）。bid/ask 皆為 0 的剔除在 read_chain（bcvs 的讀取路徑）完成（Ruby
# 業務規則層，沿用 bpus「Python 不做業務篩選」的分工）。
#
# 2026-09-25 起快取存全部列（leaps-call-spread-spec 附錄 A 決議 1）：LEAPS 垂直價差
# 需要 bid、ask 皆為 0 的列來以 last 計算「盤後參考價」，所以篩選從寫入移到讀取；
# bcvs 經 read_chain 讀到的內容與以前相同。垂直價差走 read_chain_decimal。
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
        strikes:           filter_quotable(snapshot.strikes),
        underlying_price:  snapshot.underlying_price&.to_f
      }
    end

    # 全部列（不篩選），數值一律 BigDecimal。jsonb 經 ActiveRecord 讀出是 Float，
    # 所以直接取 strikes::text 用 BigDecimal 解析，計算路徑不經過 Float（附錄 A 決議 3）。
    DECIMAL_FIELDS = %w[strike bid ask mid last delta].freeze

    def read_chain_decimal(symbol, expiration)
      row = BcvsChainSnapshot.for_symbol_and_expiration(symbol, expiration)
                             # 別名不能叫 strikes，否則 ActiveRecord 會套 jsonb 型別再解析成 Float
                             .pick(Arel.sql("strikes::text AS strikes_text"), :underlying_price, :scraped_at)
      return nil unless row

      strikes_text, underlying_price, scraped_at = row
      {
        strikes:          JSON.parse(strikes_text, decimal_class: BigDecimal).map { |r| decimalize(r) },
        underlying_price: underlying_price,
        scraped_at:       scraped_at
      }
    end

    def upsert_chain!(symbol, expiration, strikes:, underlying_price:)
      snapshot = BcvsChainSnapshot.find_or_initialize_by(symbol: symbol.upcase, expiration: expiration)
      snapshot.update!(
        strikes:           Array(strikes),
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

    # JSON 整數（例如 strike 60）解析出來是 Integer，統一轉 BigDecimal；nil 保留。
    def decimalize(row)
      DECIMAL_FIELDS.each_with_object(row.dup) do |key, out|
        out[key] = BigDecimal(out[key].to_s) if out[key].is_a?(Integer)
      end
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
