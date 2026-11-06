# frozen_string_literal: true

module HallOfFame
  # 成交日當天的每股權利金參考價（規格 P3b-3B 的來源順序）：
  # 1. barchart_dom：合約 price-history 頁 DOM 中成交日那一列的收盤。
  # 2. bs_model：只有 CDP 在線、頁面讀得到但成交日不在可見範圍內時才用。
  # CDP 離線 → cdp_offline（不得改走 bs_model）；Barchart 讀取失敗（登入失效、頁面不對）→ error，也不走 bs_model。
  class PremiumReference
    Ref = Data.define(:status, :source, :value, :underlying, :note) do
      def ok? = status == :ok
    end

    CDP_RETRY_NOTE = "CDP 未連線，待重試"

    def initialize(barchart: BarchartOptionHistory.new, underlying: UnderlyingHistory.new,
                   bs_config: OptionDescriptionParser.config.fetch("bs_model"))
      @barchart   = barchart
      @underlying = underlying
      @rate       = bs_config.fetch("risk_free_rate").to_f
      @window     = bs_config.fetch("volatility_window").to_i
    end

    def resolve(ticker:, parsed:, tx_date:, cdp_online:)
      return failure(:cdp_offline, CDP_RETRY_NOTE) unless cdp_online

      contract = BarchartOptionHistory.contract_symbol(ticker, parsed.expiration, parsed.strike, parsed.option_right)
      page     = @barchart.fetch(contract)
      return failure(:error, "Barchart #{contract} 讀取失敗（#{page['status']}）：#{page['error']}") unless %w[success empty].include?(page["status"])

      row = page.fetch("rows").find { |r| r["date"] == tx_date.iso8601 }
      return from_barchart(row, page, tx_date) if traded?(row)

      why = row ? "成交日 #{tx_date} 當天無成交（volume=#{row['volume'].inspect}、last=#{row['close'].inspect}）" : "不含成交日 #{tx_date}"
      bs_model(ticker, parsed, tx_date, "Barchart #{page['url']} 可見 #{visible_range(page)}，#{why}")
    end

    private

    def failure(status, note) = Ref.new(status:, source: nil, value: nil, underlying: nil, note:)

    # 實測：無成交日 lastPrice=0（畫面 N/A），或 volume 為 0／null 而價格沿用前一日；兩者都不是當日收盤。
    def traded?(row) = row && row["close"].to_f.positive? && row["volume"].to_i.positive?

    def from_barchart(row, page, tx_date)
      Ref.new(status: :ok, source: "barchart_dom", value: row["close"].to_d, underlying: row["underlying"]&.to_d,
              note: "Barchart DOM #{page['url']} #{tx_date} 收盤 #{row['close']}（成交量 #{row['volume']}）")
    end

    def visible_range(page)
      dates = page.fetch("rows").map { |r| r["date"] }.sort
      dates.empty? ? "0 列" : "#{dates.first}～#{dates.last}"
    end

    def bs_model(ticker, parsed, tx_date, why)
      spot  = @underlying.close_on(ticker, tx_date)
      prior = @underlying.closes_before(ticker, tx_date, @window + 1)
      return failure(:error, "#{why}；bs_model 缺 #{ticker} #{tx_date} 收盤或前 #{@window} 個交易日資料") unless spot && prior

      years = (parsed.expiration - tx_date).to_f / 365
      return failure(:error, "#{why}；成交日已過到期日，無法以 bs_model 估算") unless years.positive?

      sigma = BlackScholes.historical_volatility(prior)
      value = BlackScholes.price(s: spot, k: parsed.strike.to_f, t: years, r: @rate, sigma: sigma, right: parsed.option_right)
      Ref.new(status: :ok, source: "bs_model", value: value.to_d.round(4), underlying: spot.to_d,
              note: "#{why}；模型估算 Black-Scholes：S=#{spot.round(2)}（Yahoo #{tx_date} 收盤）、K=#{parsed.strike.to_f}、" \
                    "T=#{years.round(4)} 年、σ=#{sigma.round(4)}（前 #{@window} 交易日年化）、r=#{@rate} → #{value.round(4)}")
    end
  end
end
