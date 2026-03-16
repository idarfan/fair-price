# frozen_string_literal: true

# @label Stock Header
class FairValue::StockHeaderComponentPreview < Lookbook::Preview
  layout "component_preview"

  # @label Technology stock (default)
  # @param symbol text "Ticker symbol"
  # @param name text "Company name"
  # @param current_price number
  # @param show_52_week_range toggle
  # @param compact toggle
  def default(
    symbol: "AAPL",
    name: "Apple Inc.",
    current_price: 213.32,
    show_52_week_range: true,
    compact: false
  )
    render FairValue::StockHeaderComponent.new(
      symbol:,
      name:,
      sector: "Technology",
      industry: "Consumer Electronics",
      exchange: "NASDAQ NMS - GLOBAL MARKET",
      currency: "USD",
      current_price:,
      fifty_two_week_low: 164.08,
      fifty_two_week_high: 237.23,
      show_52_week_range:,
      compact:
    )
  end

  # @label Financial stock
  def financial_stock
    render FairValue::StockHeaderComponent.new(
      symbol: "JPM",
      name: "JPMorgan Chase & Co.",
      sector: "Financial Services",
      industry: "Banks - Diversified",
      exchange: "NYSE",
      currency: "USD",
      current_price: 245.60,
      fifty_two_week_low: 185.50,
      fifty_two_week_high: 265.30
    )
  end

  # @label REIT
  def reit
    render FairValue::StockHeaderComponent.new(
      symbol: "O",
      name: "Realty Income Corporation",
      sector: "Real Estate",
      industry: "REIT - Retail",
      exchange: "NYSE",
      current_price: 54.30,
      fifty_two_week_low: 48.20,
      fifty_two_week_high: 64.90
    )
  end

  # @label No price data
  def no_price
    render FairValue::StockHeaderComponent.new(
      symbol: "PRIVATE",
      name: "Private Company LLC",
      sector: "Technology",
      show_52_week_range: false
    )
  end
end
