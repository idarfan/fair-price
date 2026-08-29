# frozen_string_literal: true

require "rails_helper"

# 2026-08-29：`FairValue::AlertComponent` 的關閉按鈕與它的 `alert-dismiss`
# behavior 曾經是死碼——`dismissible` 預設 false，而全部 5 個呼叫端都沒有傳 true
# （只有 Lookbook preview 會），所以 ✕ 在正式站從來不會渲染。
#
# `spec/frontend/behavior_registry_spec.rb` 抓不到這種問題：它掃原始碼，看到元件裡
# 有 `behavior: "alert-dismiss"` 就算通過，但那證明的是「原始碼裡有」，不是
# 「執行時真的會渲染出來」。這支測試補的就是那一層——用真實的 request 走完整個
# flash → layout → 元件的路徑，確認掛載點真的出現在 HTML 裡。
RSpec.describe "提示訊息的關閉按鈕", type: :request do
  # ValuationsController#show 查無此股票時設 flash.now[:error] 並 render :index，
  # 由 valuations/index 交給 AlertComponent 渲染。
  #
  # 走這條而不是 #validate_ticker 的 flash[:error]，是因為後者實際上進不去：
  # 路由的 TICKER_CONSTRAINT 已經把不合法代號擋在 404，validate_ticker 的
  # 正規表示式與它等價，永遠不會失敗。
  def render_page_with_flash_alert
    allow(StockDataService).to receive(:fetch)
      .and_raise(StockDataService::NotFoundError, "找不到股票：ZZZZ（請確認代號正確）")

    get "/valuations/ZZZZ"
    expect(response).to have_http_status(:ok)
  end

  it "flash 提示帶有關閉按鈕" do
    render_page_with_flash_alert

    expect(response.body).to include("找不到股票：ZZZZ")
    expect(response.body).to include('data-dismiss="alert"')
  end

  it "flash 提示帶有 alert-dismiss 的掛載點" do
    render_page_with_flash_alert

    expect(response.body).to include('data-behavior="alert-dismiss"')
  end

  it "關閉按鈕能找得到要移除的容器" do
    render_page_with_flash_alert

    # alertDismiss.js 是 btn.closest('[data-alert]').remove()，
    # 少了 data-alert 這個外框，點下去會拋 TypeError。
    expect(response.body).to include("data-alert")
  end

  it "呼叫端仍可明確關閉這個功能" do
    html = FairValue::AlertComponent.new(message: "測試", dismissible: false).call

    expect(html).not_to include('data-dismiss="alert"')
    expect(html).not_to include('data-behavior="alert-dismiss"')
  end
end
