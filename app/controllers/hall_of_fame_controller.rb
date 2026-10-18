# frozen_string_literal: true

# 投資名人堂頁面（P5）：只負責掛載 Vite entrypoint，資料由 Api::V1::HallOfFame::* 提供。
# 人物卡隨頁面一起送出，React 首次渲染不必再打 API。
class HallOfFameController < ApplicationController
  TABS = { "congress" => "congress", "executive" => "executive" }.freeze

  def index
    tab = TABS.fetch(params[:tab].to_s, "congress")
    render HallOfFame::PageComponent.new(tab: tab, cards: HallOfFame::OfficialDirectory.new.cards("congress"))
  end
end
