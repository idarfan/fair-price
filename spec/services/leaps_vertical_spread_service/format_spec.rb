# frozen_string_literal: true

require "rails_helper"

# 下拉選項分段（2026-09-27 配色）：有資訊的文字都要帶 tone（套 ≥ 4.5:1 的顏色），
# 只有純分隔符號（「｜」「 · 」）是 nil，沿用淡灰。
RSpec.describe LeapsVerticalSpreadService::Format do
  def option(source:, price: nil, delta: "0.3")
    { expiry: "2028-01-21-m", dte: 481, strike: BigDecimal("210"), source: source,
      price: price && BigDecimal(price), delta: delta && BigDecimal(delta) }
  end

  def untoned(segments) = segments.select { |_, tone| tone.nil? }.map(&:first).uniq

  it "mid：tone 為 nil 的只有分隔符號" do
    segments = described_class.long_segments(option(source: :mid, price: "11.2"))
    expect(untoned(segments)).to contain_exactly("｜", " · ")
    expect(described_class.long_label(option(source: :mid, price: "11.2")))
      .to eq("2028-01-21 · 481 DTE｜210.00｜mid 11.20｜Δ 0.30")
  end

  it "盤後參考價：「（盤後參考價）」帶 :note，不是淡灰分隔符號" do
    segments = described_class.short_segments(option(source: :last, price: "11.2"))
    expect(segments).to include([ described_class::AFTER_HOURS_NOTE, :note ])
    expect(untoned(segments)).to eq([ "｜" ])
    expect(described_class.short_label(option(source: :last, price: "11.2"))).to eq("210.00｜last 11.20（盤後參考價）｜Δ 0.30")
  end

  it "無報價：「無報價」帶 :note" do
    segments = described_class.short_segments(option(source: nil, delta: nil))
    expect(segments).to include([ described_class::NO_QUOTE, :note ])
    expect(untoned(segments)).to eq([ "｜" ])
    expect(described_class.short_label(option(source: nil, delta: nil))).to eq("210.00｜無報價｜Δ —")
  end
end
