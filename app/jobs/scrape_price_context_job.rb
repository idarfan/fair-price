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

  # 排程鎖：擋輪詢造成的重複排程，也是輪詢端點判斷「job 還在跑」的依據。
  # 鎖的壽命＝job 的壽命：job 結束時自己解鎖，不靠 TTL 猜它跑完沒
  # （原本 3 分鐘 TTL，job 跑超過 3 分鐘就會被當成已結束）。
  # Async adapter 的 job 跑在 Rails 程序裡，server 重啟時 job 會被砍掉、
  # 鎖沒人解，所以鎖記下排程它的程序；程序換了，舊鎖直接作廢。
  # TTL 只用來清垃圾（job 卡死在同一個程序裡的最後保險），不參與判斷。
  LOCK_TTL   = 30.minutes
  LOCK_OWNER = ApplicationJob::PROCESS_TOKEN

  # 前端輪詢最多等多久（秒），由頁面 data-poll-timeout-ms 帶給 leapsPriceContext.ts。
  # 跟 job 的最長時間同一個來源：兩支爬蟲各自跑滿外層逾時、各自再等砍程序的寬限期。
  # 加 60 秒給排程延遲與 CDP 預檢，前端不會比 job 先放棄。
  POLL_BUDGET_MARGIN_S = 60

  def self.poll_budget_s
    BarchartScraperService::SCRAPER_TIMEOUTS_S.values_at("volap", "price_history").sum +
      (2 * TimedCapture::DEFAULT_KILL_GRACE_S) + POLL_BUDGET_MARGIN_S
  end

  def self.cache_key(symbol) = "price_context_job_#{symbol.to_s.upcase}"
  def self.lock_key(symbol)  = "price_context_lock_#{symbol.to_s.upcase}"

  # 「讀 → 判斷 → 寫」必須是原子的，否則同時進來的兩個輪詢請求都會讀到「沒鎖」
  # 各排一個 job。Rails.cache 的 unless_exist: 不能用：它不能覆蓋已死程序的舊鎖，
  # FileStore 的實作本身也是先 exist? 再寫。
  # 程序內 Mutex 就夠：Puma 是 single mode（config/puma.rb 沒有 workers），
  # job 走 Async adapter 也在同一個程序裡，會搶這把鎖的只有本程序的執行緒。
  # ⚠️ 改成 cluster mode 或換成獨立的 job 程序時，這裡要換成跨程序的鎖。
  LOCK_MUTEX = Mutex.new

  def self.running?(symbol) = Rails.cache.read(lock_key(symbol)) == LOCK_OWNER

  # 已經有本程序的 job 在跑就回 false；別的（已死）程序留下的鎖直接覆蓋。
  def self.acquire_lock(symbol)
    LOCK_MUTEX.synchronize do
      return false if running?(symbol)

      Rails.cache.write(lock_key(symbol), LOCK_OWNER, expires_in: LOCK_TTL)
      true
    end
  end

  def self.release_lock(symbol)
    LOCK_MUTEX.synchronize { Rails.cache.delete(lock_key(symbol)) }
  end

  def perform(symbol)
    symbol = symbol.to_s.upcase
    svc = BarchartScraperService.new(symbol)

    volap = run_isolated("volap")         { svc.fetch_volap }
    daily = run_isolated("price_history") { svc.fetch_price_history }

    # 先寫結果再解鎖：輪詢端點看到「沒鎖」時結果一定已經在了。
    Rails.cache.write(
      self.class.cache_key(symbol),
      { status: overall_status(volap, daily), volap: volap, daily: daily },
      expires_in: CACHE_TTL
    )
  ensure
    self.class.release_lock(symbol)
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
