# frozen_string_literal: true

# LEAPS 頁三個價格情境 widget 的背景抓取。
#
# 刻意**不**掛在 ScrapeLeapsJob 裡：LEAPS 查詢本身要 3–5 分鐘，widget 只要
# 十幾秒，綁在一起會讓使用者為了看價格位置多等好幾分鐘。前端拿到頁面後
# 自己輪詢 /leaps/price_context。
#
# 兩個抓取互相獨立：VOLAP 失敗不影響日線，反之亦然。任一個成功畫面就有東西看。
class ScrapePriceContextJob < ApplicationJob
  CACHE_TTL = VolapSnapshot::FRESH_WINDOW

  def self.cache_key(symbol) = "price_context_job_#{symbol.to_s.upcase}"

  def perform(symbol)
    symbol = symbol.to_s.upcase
    svc = BarchartScraperService.new(symbol)

    volap = run_isolated("volap")         { svc.fetch_volap }
    daily = run_isolated("price_history") { svc.fetch_price_history }

    Rails.cache.write(
      self.class.cache_key(symbol),
      { status: overall_status(volap, daily), volap: volap, daily: daily },
      expires_in: CACHE_TTL
    )
  end

  private

  # 兩段各自 rescue：其中一支爬蟲炸掉不該讓另一支的結果一起消失，
  # 也不該讓 job 頂層 rescue 把已經成功的部分覆蓋掉
  # （同 ScrapeLeapsJob#fetch_pmcc_short_calls_isolated 的理由）。
  def run_isolated(label)
    yield
  rescue => e
    Rails.logger.warn("[price_context] #{label} failed: #{e.class}: #{e.message}")
    { status: "error", error: e.message.first(200) }
  end

  # 只要有一邊拿到資料就算 partial，畫面至少有一張卡可看。
  def overall_status(volap, daily)
    ok = ->(r) { %w[success cached].include?(r[:status].to_s) }
    return "success" if ok.(volap) && ok.(daily)
    return "partial" if ok.(volap) || ok.(daily)

    # 兩邊都失敗：把「可行動」的原因往上帶，不要一律報 error。
    # session 過期要叫使用者去登入，no_volap_plot 要叫他去圖上掛指標，
    # 兩者的處置完全不同。
    [ volap, daily ].map { |r| r[:status].to_s }
                    .find { |s| %w[barchart_session_expired no_volap_plot].include?(s) } || "error"
  end
end
