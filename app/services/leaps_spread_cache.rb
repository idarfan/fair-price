# frozen_string_literal: true

# LEAPS 垂直價差的快取層（leaps-call-spread-spec P1，與 bcvs 完全分開）。
#
# - chain：leaps_spread_quotes，每檔履約價一列、decimal 欄位（讀出即 BigDecimal）。
#   以 (symbol, expiration) 為單位整批取代，bid、ask 皆 0 的列也存。
# - 到期日清單：Rails.cache。TTL 刻意比 30 分鐘長，過期判斷看 scraped_at——
#   選單切換到某個到期日時要能沿用舊清單，不必為了清單重跑一次 sidecar。
class LeapsSpreadCache
  FRESH_WINDOW = LeapsSpreadQuote::FRESH_WINDOW
  EXPIRATIONS_TTL = 1.day
  QUOTE_FIELDS = %w[strike bid ask last delta].freeze

  class << self
    def fresh_chain?(symbol, expiration)
      LeapsSpreadQuote.for_chain(symbol, expiration).fresh.exists?
    end

    def read_chain(symbol, expiration)
      quotes = LeapsSpreadQuote.for_chain(symbol, expiration).order(:strike).to_a
      return nil if quotes.empty?

      {
        strikes:          quotes.map { |q| q.slice(*QUOTE_FIELDS).symbolize_keys },
        underlying_price: quotes.first.underlying_price,
        scraped_at:       quotes.map(&:scraped_at).min
      }
    end

    def replace_chain!(symbol, expiration, rows:, underlying_price:, scraped_at: Time.current)
      symbol = symbol.to_s.upcase
      records = Array(rows).map do |row|
        row.to_h.stringify_keys.slice(*QUOTE_FIELDS).merge(
          "symbol" => symbol, "expiration" => expiration, "expiration_date" => Date.parse(expiration.to_s[0, 10]),
          "underlying_price" => underlying_price, "scraped_at" => scraped_at,
          "created_at" => scraped_at, "updated_at" => scraped_at
        )
      end

      LeapsSpreadQuote.transaction do
        LeapsSpreadQuote.for_chain(symbol, expiration).delete_all
        LeapsSpreadQuote.insert_all!(records) if records.any?
      end
    end

    def fresh_expirations?(symbol)
      entry = Rails.cache.read(expirations_key(symbol))
      entry.present? && entry[:scraped_at] > FRESH_WINDOW.ago
    end

    def read_expirations(symbol)
      Rails.cache.read(expirations_key(symbol))&.dig(:expirations)
    end

    def write_expirations!(symbol, expirations)
      Rails.cache.write(expirations_key(symbol), { expirations: Array(expirations), scraped_at: Time.current },
                        expires_in: EXPIRATIONS_TTL)
    end

    private

    def expirations_key(symbol) = "leaps_spread_expirations:#{symbol.to_s.upcase}"
  end
end
