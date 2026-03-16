# frozen_string_literal: true

# @label Search Bar
class FairValue::SearchBarComponentPreview < Lookbook::Preview
  layout "component_preview"

  # @label Full form (default)
  # @param ticker text "Stock ticker symbol"
  # @param discount_rate number "Discount rate percentage (6–20)"
  # @param show_discount_rate toggle "Show discount rate slider"
  # @param autofocus toggle
  def default(ticker: "AAPL", discount_rate: 10.0, show_discount_rate: true, autofocus: false)
    render FairValue::SearchBarComponent.new(
      ticker:, discount_rate:, show_discount_rate:, autofocus:
    )
  end

  # @label Compact form
  # @param ticker text
  # @param discount_rate number
  def compact(ticker: "MSFT", discount_rate: 10.0)
    render FairValue::SearchBarComponent.new(
      ticker:, discount_rate:, compact: true
    )
  end

  # @label Empty (landing)
  def empty
    render FairValue::SearchBarComponent.new(autofocus: true)
  end

  # @label Custom button text
  # @param button_text text
  # @param placeholder text
  def custom(button_text: "查詢", placeholder: "輸入代號…")
    render FairValue::SearchBarComponent.new(button_text:, placeholder:)
  end
end
