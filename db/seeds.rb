# frozen_string_literal: true

# 觀察清單現在歸屬到使用者（稽核 C-2），種子資料掛在 admin 底下；
# 沒有任何使用者時（全新環境還沒有人登入過）就跳過，等第一個 admin 出現再跑。
owner = User.find_by(admin: true) || User.order(:id).first

if owner.nil?
  puts "Skipped watchlist seeds — 尚無使用者，請先用 Google 帳號登入一次再執行 db:seed"
else
  if owner.watchlist_items.none?
    %w[AAPL MSFT NVDA TSLA AMD].each_with_index do |symbol, i|
      owner.watchlist_items.create!(symbol: symbol, position: i)
    end
    puts "Seeded #{owner.watchlist_items.count} watchlist items for #{owner.email}"
  end

  [
    { symbol: 'QQQ',  group_tag: 'index' },
    { symbol: 'SPY',  group_tag: 'index' },
    { symbol: 'IWM',  group_tag: 'index' },
    { symbol: 'SQQQ', group_tag: 'leveraged' },
    { symbol: 'TQQQ', group_tag: 'leveraged' },
    { symbol: 'GLD',  group_tag: 'macro' },
    { symbol: 'TLT',  group_tag: 'macro' }
  ].each do |attrs|
    owner.iv_watchlists.find_or_create_by(symbol: attrs[:symbol]).update(attrs)
  end
  puts "Seeded #{owner.iv_watchlists.count} IV watchlist items for #{owner.email}"
end
