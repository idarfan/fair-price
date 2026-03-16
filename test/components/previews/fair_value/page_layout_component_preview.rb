# frozen_string_literal: true

# @label Page Layout
class FairValue::PageLayoutComponentPreview < Lookbook::Preview
  # @label Landing (no ticker)
  # @param title text
  # @param show_footer toggle
  def landing(title: "FairPrice", show_footer: true)
    render FairValue::PageLayoutComponent.new(title:, show_footer:) do
      render FairValue::SearchBarComponent.new(autofocus: true)
    end
  end

  # @label With ticker in navbar
  # @param ticker text
  # @param discount_rate number
  # @param show_search_in_nav toggle
  def with_ticker(ticker: "AAPL", discount_rate: 10.0, show_search_in_nav: true)
    render FairValue::PageLayoutComponent.new(
      title: "Apple Inc. | FairPrice",
      ticker:,
      discount_rate:,
      show_search_in_nav:
    ) do
      render FairValue::AlertComponent.new(message: "分析結果將顯示在此處", type: :info)
    end
  end
end
