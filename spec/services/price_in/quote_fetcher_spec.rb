# frozen_string_literal: true

require "rails_helper"

RSpec.describe PriceIn::QuoteFetcher do
  # 規格 S0 第 8 項：test 環境的 cache_store 是 :null_store，快取永遠不命中。
  # 若不顯式換成 memory_store，下面「第二次命中快取」的案例會假通過——
  # 上游被呼叫兩次，但因為沒有斷言被跳過，測試照樣綠。
  around do |example|
    original    = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    example.run
    Rails.cache = original
  end


  def stub_quote(symbol, body:, status: 200)
    stub_request(:get, "https://finnhub.io/api/v1/quote")
      .with(query: hash_including(symbol: symbol))
      .to_return(status: status, body: body.to_json, headers: { "Content-Type" => "application/json" })
  end

  def stub_metric(symbol, metric:)
    stub_request(:get, "https://finnhub.io/api/v1/stock/metric")
      .with(query: hash_including(symbol: symbol))
      .to_return(status: 200, body: { metric: metric }.to_json,
                 headers: { "Content-Type" => "application/json" })
  end

  # 取價成功就會順帶去抓本益比；除非個案另外指定，一律給一組預設值，
  # 免得每個既有案例都得多 stub 一次。
  before do
    allow(ENV).to receive(:fetch).with("FINNHUB_API_KEY").and_return("test_key")
    stub_metric("MRVL", metric: { "epsTTM" => 3.03, "forwardPE" => 35.87 })
    # 分析師預測走 Yahoo（Finnhub 的 eps-estimate 要付費）。
    # 預設回 nil，個案要用時自己 stub。
    allow_any_instance_of(YahooFinanceService).to receive(:eps_estimates).and_return(nil)
  end

  describe "1. 合法代號、上游正常" do
    it "回傳 ok 與正確股價" do
      stub_quote("MRVL", body: { c: 223.55, t: 1_757_251_800 })
      result = described_class.call("MRVL")

      expect(result).to be_ok
      expect(result.price).to eq(223.55)
      expect(result.as_of).to eq(Time.zone.at(1_757_251_800))
      expect(result.error_code).to be_nil
    end

    it "代號小寫也能查（正規化為大寫）" do
      stub_quote("MRVL", body: { c: 223.55, t: 1_757_251_800 })
      expect(described_class.call("mrvl")).to be_ok
    end
  end

  describe "2. 相同代號連打兩次" do
    it "第二次命中快取，上游只被呼叫一次" do
      request = stub_quote("MRVL", body: { c: 223.55, t: 1_757_251_800 })

      first  = described_class.call("MRVL")
      second = described_class.call("MRVL")

      expect(request).to have_been_requested.once
      expect(second.price).to eq(first.price)
    end

    it "失敗結果不進快取（上游恢復後不必再等 15 分鐘）" do
      stub_quote("MRVL", body: {}, status: 500)
      described_class.call("MRVL")

      stub_quote("MRVL", body: { c: 223.55, t: 1_757_251_800 })
      expect(described_class.call("MRVL")).to be_ok
    end
  end

  describe "3. 上游回 404" do
    it "回傳 not_found，不拋例外" do
      stub_quote("NOPE", body: {}, status: 404)

      result = nil
      expect { result = described_class.call("NOPE") }.not_to raise_error
      expect(result).not_to be_ok
      expect(result.error_code).to eq(:not_found)
      expect(result.error_message).to eq("查無此代號")
    end

    # Finnhub 對查無的代號不回 404，而是回一組全 0 的報價。
    # 只看 HTTP 狀態碼會把「查無此代號」誤判成「這檔股票值 0 元」。
    it "上游回 200 但價格為 0 時同樣視為 not_found" do
      stub_quote("NOPE", body: { c: 0, d: nil, t: 0 })

      result = described_class.call("NOPE")
      expect(result).not_to be_ok
      expect(result.error_code).to eq(:not_found)
    end
  end

  describe "4. 上游逾時" do
    it "回傳 upstream_error，不拋例外" do
      stub_request(:get, "https://finnhub.io/api/v1/quote")
        .with(query: hash_including(symbol: "MRVL")).to_timeout

      result = nil
      expect { result = described_class.call("MRVL") }.not_to raise_error
      expect(result).not_to be_ok
      expect(result.error_code).to eq(:upstream_error)
      expect(result.error_message).to include("手動輸入")
    end

    it "上游回 500 時同樣是 upstream_error" do
      stub_quote("MRVL", body: {}, status: 500)
      expect(described_class.call("MRVL").error_code).to eq(:upstream_error)
    end

    it "上游回 429 時是 rate_limited，訊息叫使用者稍後再試" do
      stub_quote("MRVL", body: {}, status: 429)
      result = described_class.call("MRVL")
      expect(result.error_code).to eq(:rate_limited)
      expect(result.error_message).to include("稍後再試")
    end
  end

  # 本益比一律是區間：股價當天一直在動，同一個 EPS 除當日最低與最高價，
  # 得到的倍數可以差好幾倍。只報一個數字等於把那一瞬間的成交價講成公司的估值。
  describe "本益比區間" do
    it "用同一個 EPS 除當日最低與最高價，得出區間" do
      stub_quote("MRVL", body: { c: 223.59, l: 210.87, h: 223.67, t: 1_757_251_800 })

      pe = described_class.call("MRVL").pe
      expect(pe.low).to be_within(0.01).of(210.87 / 3.03)     # 69.59
      expect(pe.high).to be_within(0.01).of(223.67 / 3.03)    # 73.82
      expect(pe.current).to be_within(0.01).of(223.59 / 3.03) # 73.79
    end

    it "現價本益比必定落在當日區間之內（三者同一套算法）" do
      stub_quote("MRVL", body: { c: 223.59, l: 210.87, h: 223.67, t: 1_757_251_800 })

      pe = described_class.call("MRVL").pe
      expect(pe.current).to be_between(pe.low, pe.high)
    end

    it "Forward P/E 由現價反解預估 EPS 後，用同一組價格算區間" do
      stub_quote("MRVL", body: { c: 223.59, l: 210.87, h: 223.67, t: 1_757_251_800 })

      forward_eps = 223.59 / 35.87
      fwd = described_class.call("MRVL").forward_pe
      expect(fwd.low).to be_within(0.01).of(210.87 / forward_eps)
      expect(fwd.high).to be_within(0.01).of(223.67 / forward_eps)
    end

    # 公司過去 12 個月虧損就沒有 EPS，這是正常情況不是錯誤。
    it "epsTTM 為 null（虧損公司）時整組回 nil，仍然 ok" do
      stub_quote("LOSS", body: { c: 12.34, l: 12.0, h: 12.5, t: 1_757_251_800 })
      stub_metric("LOSS", metric: { "epsTTM" => nil })

      result = described_class.call("LOSS")
      expect(result).to be_ok
      expect(result.pe).not_to be_available
    end

    it "epsTTM 為負數（虧損）時視為無意義，回 nil" do
      stub_quote("NEG", body: { c: 12.34, l: 12.0, h: 12.5, t: 1_757_251_800 })
      stub_metric("NEG", metric: { "epsTTM" => -1.2 })

      expect(described_class.call("NEG").pe).not_to be_available
    end

    it "上游未提供當日高低價時仍給得出現價本益比" do
      stub_quote("MRVL", body: { c: 223.59, t: 1_757_251_800 })

      pe = described_class.call("MRVL").pe
      expect(pe.current).to be_within(0.01).of(223.59 / 3.03)
      expect(pe.low).to be_nil
    end

    it "本益比端點掛掉不影響股價帶入" do
      stub_quote("MRVL", body: { c: 223.55, l: 220.0, h: 224.0, t: 1_757_251_800 })
      stub_request(:get, "https://finnhub.io/api/v1/stock/metric")
        .with(query: hash_including(symbol: "MRVL")).to_timeout

      result = described_class.call("MRVL")
      expect(result).to be_ok
      expect(result.price).to eq(223.55)
      expect(result.pe).not_to be_available
    end
  end

  # 2026-09-07 事故：Result 從「單一 pe_ttm」改成「pe 區間」後，快取裡舊結構的
  # 物件反序列化撞上新結構 → TypeError → 500。使用者看到的錯誤訊息
  # （「報價格式無法解析」）跟真正原因毫無關係。
  describe "分析師 EPS 預測區間" do
    it "帶回 low／high 兩端，不是平均值（色帶要畫的是分歧程度）" do
      stub_quote("MRVL", body: { c: 223.59, l: 210.87, h: 223.67, t: 1_757_251_800 })
      allow_any_instance_of(YahooFinanceService).to receive(:eps_estimates).and_return(
        { current_year: { low: 3.92, high: 4.34, avg: 4.20, analysts: 36, end_date: "2027-01-31" },
          next_year:    { low: 5.65, high: 8.09, avg: 6.72, analysts: 40, end_date: "2028-01-31" } }
      )

      est = described_class.call("MRVL").eps_estimate
      expect(est).to be_available
      expect(est.low).to eq(3.92)
      expect(est.high).to eq(4.34)
      expect(est.analysts).to eq(36)
    end

    it "上游抓不到預測時不算錯誤，仍回得出股價" do
      stub_quote("MRVL", body: { c: 223.59, l: 210.87, h: 223.67, t: 1_757_251_800 })

      result = described_class.call("MRVL")
      expect(result).to be_ok
      expect(result.price).to eq(223.59)
      expect(result.eps_estimate).not_to be_available
    end

    it "Yahoo 拋例外時不影響股價帶入" do
      stub_quote("MRVL", body: { c: 223.59, l: 210.87, h: 223.67, t: 1_757_251_800 })
      allow_any_instance_of(YahooFinanceService).to receive(:eps_estimates).and_raise(StandardError, "boom")

      result = nil
      expect { result = described_class.call("MRVL") }.not_to raise_error
      expect(result).to be_ok
      expect(result.eps_estimate).not_to be_available
    end
  end

  describe "快取結構變動的韌性" do
    it "快取內容壞掉時重抓，不拋例外也不回錯誤" do
      stub_quote("MRVL", body: { c: 223.59, l: 210.87, h: 223.67, t: 1_757_251_800 })
      # 模擬快取裡放著不是 Hash 的東西（舊版本存的是 Data 物件）
      Rails.cache.write("price_in:quote:v3:MRVL", "不是 Hash 的東西")

      result = nil
      expect { result = described_class.call("MRVL") }.not_to raise_error
      expect(result).to be_ok
      expect(result.price).to eq(223.59)
    end

    it "快取存的是 Hash 而不是 Data 物件（Data 的 Marshal 綁死欄位數量）" do
      stub_quote("MRVL", body: { c: 223.59, l: 210.87, h: 223.67, t: 1_757_251_800 })
      described_class.call("MRVL")

      expect(Rails.cache.read("price_in:quote:v3:MRVL")).to be_a(Hash)
    end

    it "快取內容缺欄位時不炸開，缺的部分為 nil" do
      Rails.cache.write("price_in:quote:v3:MRVL", { ok: true, price: 1.0 })

      result = nil
      expect { result = described_class.call("MRVL") }.not_to raise_error
      expect(result.price).to eq(1.0)
      expect(result.pe).not_to be_available
    end

    it "快取命中時仍還原出完整的區間物件" do
      stub_quote("MRVL", body: { c: 223.59, l: 210.87, h: 223.67, t: 1_757_251_800 })

      first  = described_class.call("MRVL")
      second = described_class.call("MRVL")

      expect(second.pe.to_h).to eq(first.pe.to_h)
      expect(second.forward_pe.to_h).to eq(first.forward_pe.to_h)
      expect(second.eps_ttm).to eq(first.eps_ttm)
    end
  end

  describe "邊界" do
    it "空字串代號直接回 not_found，不打上游" do
      expect(described_class.call("").error_code).to eq(:not_found)
      expect(a_request(:get, /finnhub/)).not_to have_been_made
    end

    it "上游未提供時間戳時以現在時間代替" do
      stub_quote("MRVL", body: { c: 223.55, t: 0 })
      expect(described_class.call("MRVL").as_of).to be_within(5.seconds).of(Time.current)
    end
  end
end
