# frozen_string_literal: true

module HallOfFame
  # React 掛載點。載入前先輸出標題、分頁名稱與人物名單的純文字，讓頁面在 JS 失敗時仍可辨識。
  class PageComponent < ApplicationComponent
    TAB_LABELS = { "congress" => "國會議員", "executive" => "行政政要" }.freeze

    def initialize(tab:, cards:)
      @tab   = tab
      @cards = cards
    end

    def view_template
      div(id: "hall-of-fame-root", data: { tab: @tab, cards: @cards.to_json }) do
        h1(class: "text-xl font-bold text-gray-900 mb-2") { plain("投資名人堂") }
        p(class: "text-sm text-gray-500") { plain(TAB_LABELS.values.join("｜")) }
        p(class: "text-sm text-gray-400 mt-2") { plain("載入中… #{@cards.map { |c| c[:display_name] }.join('、')}") }
      end
    end
  end
end
