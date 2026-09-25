class FetchLog < ApplicationRecord
  # ⚠️ 兩份白名單都必須跟得上 lib/barchart_scrapers/*.py 與 BarchartScraperService。
  # 漏掉一個值不會炸，只會讓那筆稽核記錄**安靜地寫不進來**——log_fetch 把
  # 例外 rescue 成一行 warn，畫面與資料庫都看不出少了東西。
  # 2026-09-21 實際踩到：volap 與 price_history 兩種抓取從上線起一筆都沒記錄。
  # 同 feedback_scraper_status_case：新增 scraper 狀態時，這裡要一起改。
  #
  # status 的來源有兩種：scraper 的 JSON（success／error／barchart_session_expired／
  # no_candidates／partial／invalid_strike／dom_structure_changed／charts_not_ready／
  # chart_not_ready／no_volap_plot／volap_timeout），以及 service 自己產生的
  # cached／partial_error。
  STATUSES = %w[
    success cached error partial partial_error
    barchart_session_expired dom_structure_changed
    no_candidates invalid_strike
    charts_not_ready chart_not_ready no_volap_plot volap_timeout
    symbol_not_found no_options
  ].freeze

  FETCH_TYPES = %w[
    technical fundamental options_flow max_pain leaps pmcc_short
    bpus_expirations bpus_put_chain bpus_volatility
    bcvs_expirations bcvs_call_chain
    volap price_history
  ].freeze

  validates :symbol, :fetch_type, :status, :fetched_at, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :fetch_type, inclusion: { in: FETCH_TYPES }

  scope :recent_failures, -> {
    where.not(status: "success").order(fetched_at: :desc).limit(50)
  }
end
