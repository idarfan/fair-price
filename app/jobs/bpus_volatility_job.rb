# frozen_string_literal: true

# bpus-fix.md 項目6：背景抓 Volatility 資料，不寫 bpus_job_ 快取（沒有輪詢
# UI），結果直接進 BarchartScraperService#fetch_bpus_volatility 自己的 15
# 分鐘快取；controller#volatility 之後直接讀那份快取即可。失敗只記錄，不重試
# ——純背景輔助資訊，使用者重新整理頁面會自然再觸發一次。
class BpusVolatilityJob < ApplicationJob
  def perform(symbol, expiration)
    BarchartScraperService.new(symbol).fetch_bpus_volatility(expiration: expiration)
  rescue => e
    Rails.logger.warn("[bpus] volatility background fetch failed: #{e.message}")
  end
end
