# frozen_string_literal: true

require "rails_helper"

# 2026-08-29：`ValuationsController#validate_ticker` 曾經是死碼——HTML 路由的
# TICKER_CONSTRAINT 與它的正規表示式等價，不合法的代號在路由層就被擋成 404，
# 那段「無效的股票代號」的友善提示永遠不會執行。
#
# 但搜尋列（tickerSearch.ts）只檢查非空就直接 `window.location.href = ...`，
# 所以使用者打「台積電」或帶空白的代號，看到的是原始 404 頁。
# 現在 HTML 路由收下整個 segment，由 controller 驗證並導回首頁。
RSpec.describe "估值頁的代號驗證", type: :request do
  describe "合法代號" do
    it "純字母代號進得了 show" do
      allow(StockDataService).to receive(:fetch)
        .and_raise(StockDataService::NotFoundError, "找不到股票：AAPL")

      get "/valuations/AAPL"

      expect(response).to have_http_status(:ok)
      expect(StockDataService).to have_received(:fetch).with("AAPL")
    end

    # 放寬 constraint 之後如果忘了 format: false，Rails 會把 .B 當成格式後綴切掉。
    it "含小數點的代號不會被當成格式後綴切掉（BRK.B）" do
      allow(StockDataService).to receive(:fetch)
        .and_raise(StockDataService::NotFoundError, "找不到股票：BRK.B")

      get "/valuations/BRK.B"

      expect(response).to have_http_status(:ok)
      expect(StockDataService).to have_received(:fetch).with("BRK.B")
    end
  end

  describe "不合法代號" do
    {
      "含空白"      => "AAPL X",
      "非 ASCII"    => "台積電",
      "含特殊字元"  => "!!!",
      "超過 10 字"  => "TOOOOOOLONGTICKER"
    }.each do |label, bad|
      it "#{label} 導回首頁並顯示提示，而不是 404" do
        get "/valuations/#{CGI.escape(bad)}"

        expect(response).to redirect_to(root_path)
        expect(flash[:error]).to eq("無效的股票代號")
      end
    end

    # 壞掉的百分比編碼由 Rails 的 middleware 先擋成 400，進不到 controller。
    # controller 裡的 valid_encoding? 是第二道防線（少了它，無效 UTF-8 丟給
    # match? 會拋 ArgumentError 變成 500）。這裡釘住的是「不會是 500」。
    it "壞掉的百分比編碼是 400，不是 500" do
      get "/valuations/%FF%FE"

      expect(response).to have_http_status(:bad_request)
    end
  end

  # API 端維持嚴格 constraint：對 API 而言 404 才是對的回應，不該導頁。
  it "API 端的不合法代號仍然是 404，不會被導頁" do
    get "/api/v1/valuations/#{CGI.escape('台積電')}"

    expect(response).to have_http_status(:not_found)
  end
end
