# frozen_string_literal: true

require "rails_helper"

RSpec.describe "版本更新說明", type: :request do
  # 版本號由 RELEASE_NOTES.first[:date] 推導（ApplicationHelper#app_version），
  # 加一筆新的更新說明就會自動反映到頁尾與彈窗標題。這裡把那條連動鎖住：
  # 之後若有人改了 app_version 的實作，忘了同步就會被抓到。
  let(:latest) { RELEASE_NOTES.first }

  before { get "/price_in" }

  it "頁尾顯示最新版本號" do
    expect(response.body).to include("v#{latest[:date]}")
  end

  it "彈窗標題也顯示同一個版本號" do
    versions = response.body.scan(/v#{latest[:date]}/)
    expect(versions.length).to be >= 2   # 頁尾 + 彈窗標題
  end

  it "彈窗內容為最新一筆的標題與所有項目" do
    expect(response.body).to include(CGI.escapeHTML(latest[:title]))
    latest[:items].each { |item| expect(response.body).to include(CGI.escapeHTML(item)) }
  end

  it "RELEASE_NOTES 依日期由新到舊排列（first 必須是最新）" do
    dates = RELEASE_NOTES.map { |n| n[:date] }
    expect(dates).to eq(dates.sort.reverse)
  end
end
