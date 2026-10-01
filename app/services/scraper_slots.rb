# frozen_string_literal: true

# 全站同時執行的 Barchart 爬蟲上限。所有爬蟲共用一個 Chrome（9222），
# 每支各開一個分頁（cdp_helper.get_target），同時太多會把 Chrome 壓垮。
#
# 原本的上限是隱性的：Async adapter 執行緒池 max_threads = RAILS_MAX_THREADS（3），
# 剛好讓背景工作最多 3 個。但那個值也是 Puma 處理網頁請求的執行緒數，
# 調大它抓取上限會跟著變大。這裡把上限寫死成自己的常數。
#
# 程序內號誌就夠：Puma single mode＋Async adapter，所有爬蟲都在本程序啟動
# （同 ScrapePriceContextJob::LOCK_MUTEX 的前提；改 cluster mode 時要換跨程序的做法）。
#
# 垂直價差的 sidecar（LeapsCallChainFetcher::SidecarRunner）刻意不走這裡（使用者裁示）：
# 它跑在 HTTP 請求裡，排隊會佔住 Puma 執行緒，3 個人同時等就整站卡住；
# 它本身也已被 Puma 的 3 個執行緒限制在最多 3 個。
class ScraperSlots
  MAX_CONCURRENT = 3

  def self.instance = INSTANCE

  def self.with_slot(&) = instance.with_slot(&)

  def initialize(limit)
    @semaphore = Concurrent::Semaphore.new(limit)
  end

  def with_slot
    @semaphore.acquire
    begin
      yield
    ensure
      @semaphore.release
    end
  end

  INSTANCE = new(MAX_CONCURRENT)
end
