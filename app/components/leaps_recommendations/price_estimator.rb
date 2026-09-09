# frozen_string_literal: true

module LeapsRecommendations::PriceEstimator
  # 「價格預估」試算 Modal：全頁共用一份 DOM，點擊任一列的「📈 試算」按鈕時
  # 由 render_price_estimator_script 讀該按鈕的 data-* 帶入試算參數（見該按鈕
  # 於 render_candidate_row 的定義）。不隨列重複渲染。
  def render_price_estimator_modal
    div(id: "leaps-price-estimator-overlay", class: "leaps-pe-overlay hidden") do
      div(id: "leaps-price-estimator-panel", class: "leaps-pe-panel") do
        div(class: "leaps-pe-header") do
          # 標題列同時是拖動把手：淺綠色帶 ＋ cursor: grab 已經把這件事講清楚，
          # 不在標題文字裡加註「可拖動」——需要用文字解釋的介面，通常是視覺沒做到位。
          h3(class: "leaps-pe-title") { plain "LEAPS Call 價格預估試算" }
          button(type: "button", id: "leaps-pe-close", class: "leaps-pe-close",
                 aria_label: "關閉", title: "關閉（Esc）") { plain "✕" }
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
          # 0–100：原本上限 50 會把高 IV 合約夾住——SHOP 的 57.3% 開起來
          # 滑桿頂在最右、顯示 50.0%，看起來像是「這檔 IV 只有 50」。
          # sigma 為 0 時 bsCall 回 nil，結果顯示破折號，不會拋錯。
          #
          # value 只是 JS 還沒接手前的佔位：開啟試算時會被該列合約的原始 IV
          # 覆寫（見 price_estimator.js 的 openModal）。
          input(type: "range", id: "leaps-pe-iv", class: "leaps-pe-slider",
                min: "0", max: "100", step: "0.1", value: "50")
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
            span(class: "leaps-pe-result-label leaps-pe-result-label-diff") { plain "與目前 Mid 差異" }
            span(id: "leaps-pe-result-diff", class: "leaps-pe-result-value leaps-pe-result-diff-value")
          end
        end
      end
    end
  end
end
