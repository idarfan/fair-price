# @label Ownership::PageComponent
class Ownership::PageComponentPreview < Lookbook::Preview
  # @label 有股票清單
  def with_symbols
    render Ownership::PageComponent.new(
      symbols:  %w[AAPL TSLA NVDA MSFT GOOGL],
      selected: "AAPL"
    )
  end

  # @label 空清單（Watchlist 無股票）
  def empty
    render Ownership::PageComponent.new(
      symbols:  [],
      selected: nil
    )
  end
end
