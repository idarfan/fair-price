# frozen_string_literal: true

class StrikeChainSnapshot < ApplicationRecord
  validates :symbol,     presence: true
  validates :strikes,    presence: true
  validates :scraped_at, presence: true

  TOLERANCE_FALLBACK_RATIO = 0.10

  def min_strike = strikes.min
  def max_strike = strikes.max

  def tolerance
    return max_strike * TOLERANCE_FALLBACK_RATIO if strikes.size <= 1

    spacings = strikes.each_cons(2).map { |a, b| b - a }
    spacings.sum / spacings.size
  end

  def valid_strike?(user_strike)
    s = user_strike.to_f
    s >= (min_strike - tolerance) && s <= (max_strike + tolerance)
  end

  # strikes 是第一個 LEAPS 到期日的完整履約價鏈（leaps_scraper.py 的 chain_snapshot）。
  # valid_strike? 只看範圍；範圍內但沒掛牌的履約價（每 5 一檔時的 81）要另外擋，
  # 否則排 job 抓完只會得到空結果（leaps-deep-itm-fix.md P3 T2b）。
  LISTED_EPSILON = 1e-6

  def listed?(user_strike)
    s = user_strike.to_f
    strikes.any? { |k| (k.to_f - s).abs < LISTED_EPSILON }
  end

  # 判斷依據是第一個 LEAPS 到期日的鏈（使用者裁示 (i)），訊息要講明，
  # 以免只在更遠到期日掛牌的履約價被誤會成「整條鏈都沒有」。
  def unlisted_message(symbol, user_strike, expiration_date)
    basis = expiration_date ? "第一個 LEAPS 到期日（#{expiration_date.iso8601}）" : "第一個 LEAPS 到期日"
    "Strike #{user_strike} 不在 #{symbol} #{basis}的期權鏈上（期權鏈無此履約價），" \
      "請改選有掛牌的履約價，或留空讓系統自動偵測。"
  end

  def invalid_message(symbol, user_strike)
    p = spot_price ? "$#{format('%.2f', spot_price)}" : "不明"
    "Strike #{user_strike} 不在 #{symbol} 的履約價範圍" \
      "（實際範圍 $#{format('%.2f', min_strike)}–$#{format('%.2f', max_strike)}，現價 #{p}），請重新輸入"
  end
end
