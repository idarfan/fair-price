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
RSpec.describe IvWatchlist do
  let(:user) { create(:user) }

  it "小寫輸入會被正規化成大寫" do
    item = described_class.create!(user: user, symbol: "aapl", group_tag: "general")
    expect(item.symbol).to eq("AAPL")
  end

  it "同一使用者的小寫重複是驗證錯誤" do
    described_class.create!(user: user, symbol: "AAPL", group_tag: "general")

    dup = described_class.new(user: user, symbol: "aapl", group_tag: "general")

    expect(dup).not_to be_valid
    expect(dup.errors[:symbol]).to be_present
  end

  it "不同使用者可以有相同代號（唯一性是 scope 到 user）" do
    other = create(:user)
    described_class.create!(user: user,  symbol: "AAPL", group_tag: "general")

    expect(described_class.new(user: other, symbol: "aapl", group_tag: "general")).to be_valid
  end

  it "前後空白會先被去掉，不會被 format 驗證擋下" do
    # 正規化在 before_save 時，format 驗證看到的是 " aapl "，空白不符
    # /\A[A-Za-z\-\.]{1,10}\z/ 而被誤擋。搬到 before_validation 後才正確。
    item = described_class.new(user: user, symbol: "  aapl  ", group_tag: "general")

    expect(item).to be_valid
    expect(item.symbol).to eq("AAPL")
  end
end
