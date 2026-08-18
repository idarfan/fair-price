# frozen_string_literal: true

module LeapsRecommendations::VocabCards
  include LeapsRecommendations::SharedConstants

  # 術語字卡區：<details> 收合、深色卡面、rotateY 翻面、🔊 Web Speech 發音。
  # data-export-exclude：教學元素不入匯出畫面（與導覽/匯出按鈕同規則）。
  def render_vocab_cards
    details(class: "bg-white rounded-xl border border-gray-200 shadow-sm", data_export_exclude: "") do
      summary(class: "leaps-vocab-summary") { plain "📚 術語字卡（點擊翻面 · 🔊 聽發音）" }
      div(class: "px-4 pb-4") do
        div(class: "leaps-vocab-grid") do
          VOCAB_CARDS.each { |card| render_vocab_card(card) }
        end
      end
    end
  end


  def render_vocab_card(card)
    div(class: "leaps-vocab-card") do
      div(class: "leaps-vocab-inner") do
        div(class: "leaps-vocab-front") do
          button(class: "speak-btn", type: "button", data_term: card[:en],
                 aria_label: "朗讀 #{card[:en]}") { plain "🔊" }
          div(class: "leaps-vc-en")   { plain card[:en] }
          div(class: "leaps-vc-ipa")  { plain card[:ipa] }
          div(class: "leaps-vc-zh")   { plain card[:zh] }
          div(class: "leaps-vc-hint") { plain card[:hint] }
        end
        div(class: "leaps-vocab-back") do
          div(class: "leaps-vc-back-title") { plain "#{card[:en]} — #{card[:zh]}" }
          div(class: "leaps-vc-back-body")  { plain card[:back] }
          div(class: "leaps-vc-example")    { plain card[:ex] }
        end
      end
    end
  end
end
