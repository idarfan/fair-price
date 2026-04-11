# frozen_string_literal: true

module Api
  module V1
    class OptionsController < Api::V1::BaseController
      CACHE_TTL = 5.minutes

      # GET /api/v1/options/:symbol/chain?date=YYYY-MM-DD
      def chain
        symbol = sanitize_symbol(params[:symbol])
        render json: mock_chain(symbol)
      end

      # GET /api/v1/options/:symbol/sentiment
      def sentiment
        symbol = sanitize_symbol(params[:symbol])
        render json: mock_sentiment(symbol)
      end

      # GET /api/v1/options/:symbol/iv_rank
      def iv_rank
        symbol = sanitize_symbol(params[:symbol])
        data = Rails.cache.fetch("iv_rank/#{symbol}", expires_in: CACHE_TTL) do
          IvRankService.new(symbol).call
        end
        render json: data
      end

      # POST /api/v1/options/analyze_image
      # Body: multipart/form-data { image: <file> }
      def analyze_image
        image = params[:image]
        return render json: { error: "請上傳圖片" }, status: :unprocessable_entity if image.blank?

        unless image.content_type.to_s.start_with?("image/")
          return render json: { error: "只接受圖片格式（JPG / PNG / WebP）" }, status: :unprocessable_entity
        end

        system_data = parse_system_data(params[:system_data])
        Rails.logger.info("[OptionsOCR] system_data keys=#{system_data.keys} iv_rank=#{system_data['iv_rank']} current_hv=#{system_data['current_hv']}")
        result = OptionsOcrService.new(image, system_data: system_data).call
        render json: result
      rescue => e
        render json: { error: e.message }, status: :unprocessable_entity
      end

      # POST /api/v1/options/strategy_recommend
      # Body: { symbol, outlook, iv_rank }
      def strategy_recommend
        symbol   = sanitize_symbol(params[:symbol])
        outlook  = params[:outlook].to_s
        iv_rank  = params[:iv_rank].to_f
        iv_env   = iv_rank >= 50 ? "high_iv" : "low_iv"

        strategies = StrategyRecommender::STRATEGIES.dig(outlook.to_sym, iv_env.to_sym) ||
                     StrategyRecommender::STRATEGIES.dig(outlook.to_sym, :any) || []

        render json: {
          symbol:    symbol,
          outlook:   outlook,
          iv_rank:   iv_rank,
          iv_env:    iv_env,
          strategies: strategies
        }
      end

      private

      def sanitize_symbol(raw)
        raw.to_s.upcase.gsub(/[^A-Z0-9.\-]/, "").first(10)
      end

      def parse_system_data(raw)
        return {} if raw.blank?
        JSON.parse(raw).slice("symbol", "price", "iv_rank", "current_hv", "hv_high", "hv_low", "iv_comment", "peers")
      rescue JSON::ParserError
        {}
      end

      # ── Mock data（後續替換為 YahooOptionsService 呼叫）─────────────

      def mock_chain(symbol)
        price = mock_price(symbol)
        {
          symbol:       symbol,
          current_price: price,
          expirations:  upcoming_fridays(4),
          calls: mock_contracts(symbol, price, :call),
          puts:  mock_contracts(symbol, price, :put)
        }
      end

      def mock_sentiment(symbol)
        price = mock_price(symbol)
        {
          symbol:            symbol,
          price:             price,
          pc_ratio:          1.18,
          pc_ratio_sentiment: "偏空（市場避險需求高）",
          call_volume:       142_000,
          put_volume:        167_560,
          iv_skew:           0.14,
          otm_put_iv:        0.68,
          otm_call_iv:       0.54,
          skew_comment:      "Put Skew 偏高，市場高度警戒下行風險",
          oi_distribution:   mock_oi(price)
        }
      end

      def fetch_price(symbol)
        Rails.cache.fetch("options_price/#{symbol}", expires_in: 5.minutes) do
          quote = FinnhubService.new.quote(symbol)
          price = quote&.dig("c").to_f
          price > 0 ? price : nil
        end
      end

      def mock_price(symbol)
        fetch_price(symbol) ||
          { "NVDA" => 875.50, "AAPL" => 213.40, "TSLA" => 248.80,
            "AMD"  => 162.30, "SPY"  => 547.20 }.fetch(symbol, 0.0)
      end

      def mock_contracts(symbol, price, type)
        strikes = (price * 0.85).ceil(-1).step(price * 1.15, 5.0).first(12)
        strikes.map do |k|
          iv  = type == :put ? 0.55 + (price - k) / price * 0.2 : 0.50
          bid = [((type == :call ? [price - k, 0].max : [k - price, 0].max) + iv * price * 0.05).round(2), 0.05].max
          {
            contract_symbol: "#{symbol}#{type.to_s.upcase[0]}#{k.to_i}",
            strike:          k.round(2),
            bid:             bid,
            ask:             (bid * 1.05).round(2),
            mid:             (bid * 1.025).round(2),
            iv:              iv.round(4),
            volume:          rand(500..8000),
            open_interest:   rand(1000..25_000),
            in_the_money:    type == :call ? price > k : price < k,
            dte:             30
          }
        end
      end

      def mock_oi(price)
        (0..10).map do |i|
          strike = (price * 0.88 + i * price * 0.025).round(0)
          {
            strike:   strike,
            call_oi:  (rand(1000..20_000) * (strike > price ? 1.5 : 0.8)).to_i,
            put_oi:   (rand(1000..15_000) * (strike < price ? 1.4 : 0.7)).to_i
          }
        end
      end

      def upcoming_fridays(count)
        date = Date.today
        date += 1 until date.friday?
        count.times.map { |i| (date + i * 7).to_s }
      end
    end
  end
end
