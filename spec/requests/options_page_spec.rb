# frozen_string_literal: true

require "rails_helper"

# 2026-08-29：`/options/:symbol` 從 ca052af 起就一直是 500。
#
# `OptionsController#show` 寫成 `render Options::PageComponent.new(...)`，少了
# 前綴 `::`。controller 繼承鏈上有 ActionController::ParamsWrapper::Options，
# Ruby 的常數查找會先命中它，於是拋
# `NameError (uninitialized constant ActionController::ParamsWrapper::Options::PageComponent)`。
#
# `#index` 一直寫的是 `::Options::PageComponent`，所以 /options 正常、
# /options/:symbol 全掛——兩個 action 只差一個 `::`，肉眼很難發現。
RSpec.describe "Options Analyzer 頁面", type: :request do
  it "GET /options 正常渲染" do
    get "/options"

    expect(response).to have_http_status(:ok)
  end

  it "GET /options/:symbol 正常渲染（常數解析不可依賴 controller 作用域）" do
    get "/options/AAPL"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("AAPL")
  end

  it "小寫代號會被轉成大寫" do
    get "/options/aapl"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("AAPL")
  end

  # 註：sanitize_symbol 裡的 gsub(/[^A-Z0-9.\-]/, "") 實務上進不去——
  # 路由的 TICKER_CONSTRAINT 已經把非法字元擋成 404（與 valuations 同一個模式）。
  # 這裡釘住的是「非法代號是 404，不是 500」。
  it "非法代號是 404，不是 500" do
    get "/options/#{CGI.escape('aapl!!')}"

    expect(response).to have_http_status(:not_found)
  end
end
