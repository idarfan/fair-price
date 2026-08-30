# frozen_string_literal: true

require "rails_helper"

# 2026-08-30 稽核（database_consistency）：本 model 原本寫
# `uniqueness: { case_sensitive: false }`。那個寫法有兩個問題：
#
#   1. 代號存檔前一律 upcase，DB 裡只有大寫，比對大小寫毫無意義；
#      而 case_sensitive: false 會產生 LOWER(...) = LOWER($1)，
#      用不到既有的 btree 唯一索引。
#   2. 正規化原本寫在 before_save——也就是驗證「之後」。單獨拿掉
#      case_sensitive: false 會讓 "aapl" 通過唯一性驗證、存檔時才
#      upcase 成 "AAPL" 撞上唯一索引，使用者看到 500 而不是驗證錯誤。
#
# 所以正規化被搬到 before_validation。下面釘住的就是那個順序：
# 少了這些測試，把 before_validation 改回 before_save 不會有任何測試失敗。
RSpec.describe WatchedTicker do
  it "小寫重複是驗證錯誤" do
    described_class.create!(ticker: "AAPL")

    expect(described_class.new(ticker: "aapl")).not_to be_valid
  end
end
