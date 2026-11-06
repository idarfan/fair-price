# frozen_string_literal: true

require "rails_helper"

RSpec.describe HallOfFame::OptionDescriptionParser do
  subject(:parser) { described_class.new }

  it "parses Pelosi's purchased-calls wording and expands a two-digit year" do
    parsed = parser.parse("Purchased 200 call options with a strike price of $50 and an expiration date of 3/19/27.")

    expect(parsed).to have_attributes(pattern: "purchased_or_sold", option_right: "call", strike: BigDecimal("50"),
                                      expiration: Date.new(2027, 3, 19), contracts_stated: 200, exercise: false)
  end

  it "parses the semicolon list wording without contracts" do
    parsed = parser.parse("Call options; Strike price $340; Expires 10/16/2026")

    expect(parsed).to have_attributes(pattern: "semicolon_list", option_right: "call", strike: BigDecimal("340"),
                                      expiration: Date.new(2026, 10, 16), contracts_stated: nil)
  end

  it "flags exercised options" do
    parsed = parser.parse("Exercised 50 call options purchased 1/14/25 (5,000 shares) at a strike price of $20 " \
                          "with an expiration date of 1/16/26.")

    expect(parsed).to have_attributes(exercise: true, contracts_stated: 50, strike: BigDecimal("20"), expiration: Date.new(2026, 1, 16))
  end

  it "returns nil instead of guessing for incomplete descriptions" do
    expect(parser.parse("10 puts at $22.00")).to be_nil
    expect(parser.parse(nil)).to be_nil
    expect(parser.parse("Call options; Strike price $340; Expires 13/45/2026")).to be_nil
  end

  it "detects option trades by asset code or description" do
    expect(described_class.option_trade?(build(:hof_trade, asset_type_code: "OP", description: nil))).to be(true)
    expect(described_class.option_trade?(build(:hof_trade, asset_type_code: "ST", description: "Exercised 5 put options"))).to be(true)
    expect(described_class.option_trade?(build(:hof_trade, asset_type_code: "ST", description: "Purchased 10,000 shares."))).to be(false)
  end
end
