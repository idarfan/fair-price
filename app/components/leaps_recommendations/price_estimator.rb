# frozen_string_literal: true

module LeapsRecommendations::PriceEstimator
  # 「價格預估」試算 Modal：全頁共用一份 DOM，點擊任一列的「📈 試算」按鈕時
  # 由 render_price_estimator_script 讀該按鈕的 data-* 帶入試算參數（見該按鈕
  # 於 render_candidate_row 的定義）。不隨列重複渲染。
  def render_price_estimator_modal
    div(id: "leaps-price-estimator-overlay", class: "leaps-pe-overlay hidden") do
      div(id: "leaps-price-estimator-panel", class: "leaps-pe-panel") do
        div(class: "leaps-pe-header") do
          h3(class: "leaps-pe-title") { plain "LEAPS Call 價格預估試算" }
          button(type: "button", id: "leaps-pe-close", class: "leaps-pe-close", aria_label: "關閉") { plain "✕" }
        end

        div(id: "leaps-pe-contract-info", class: "leaps-pe-contract-info")

        div(class: "leaps-pe-field") do
          input(type: "number", id: "leaps-pe-spot", class: "leaps-pe-input",
                step: "0.01", placeholder: "請輸入預期的股價")
        end

        div(class: "leaps-pe-field") do
          label(class: "leaps-pe-label", for: "leaps-pe-iv") do
            plain "IV% "
            span(id: "leaps-pe-iv-value")
          end
          input(type: "range", id: "leaps-pe-iv", class: "leaps-pe-slider", min: "10", max: "50", step: "0.1")
        end

        div(class: "leaps-pe-results") do
          div(class: "leaps-pe-result-row") do
            span(class: "leaps-pe-result-label") { plain "推估 Mid 價格" }
            span(id: "leaps-pe-result-mid", class: "leaps-pe-result-value leaps-pe-result-primary")
          end
          div(class: "leaps-pe-result-row") do
            span(class: "leaps-pe-result-label") { plain "內在價值" }
            span(id: "leaps-pe-result-intrinsic", class: "leaps-pe-result-value")
          end
          div(class: "leaps-pe-result-row") do
            span(class: "leaps-pe-result-label") { plain "時間價值" }
            span(id: "leaps-pe-result-time-value", class: "leaps-pe-result-value")
          end
          div(class: "leaps-pe-result-row") do
            span(class: "leaps-pe-result-label") { plain "與目前 Mid 差異" }
            span(id: "leaps-pe-result-diff", class: "leaps-pe-result-value")
          end
        end
      end
    end
  end
end
