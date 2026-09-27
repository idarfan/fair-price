# frozen_string_literal: true

require "rails_helper"

# leaps-call-spread-spec P7：到期日預估股價 → 到期損益（每口 × 100）與報酬率。
# 例：K_L 100、K_S 160、mid 淨成本 48.075 → 最大虧損 4,807.50、最大獲利 1,192.50、兩平 148.075。
RSpec.describe LeapsVerticalSpreadService::Payoff do
  def call(target, long_strike: "100", short_strike: "160", d_mid: "48.075")
    described_class.call(long_strike: long_strike, short_strike: short_strike, d_mid: d_mid, target_price: target)
  end

  it "預估價低於買入腳：虧掉全部淨成本（= 最大虧損），報酬率 -100%" do
    result = call("90")
    expect(result[:pnl]).to eq(BigDecimal("-4807.5"))
    expect(result[:display]).to eq(pnl: "-$4,807.50", pct: "-100.00%")
    expect(result[:tone]).to eq(:loss)
  end

  it "預估價介於買入腳與兩平點：部分虧損" do
    result = call("120")
    expect(result[:pnl]).to eq(BigDecimal("-2807.5"))
    expect(result[:display][:pct]).to eq("-58.40%")
    expect(result[:tone]).to eq(:loss)
  end

  it "預估價剛好在兩平點：損益 0" do
    result = call("148.075")
    expect(result[:pnl]).to eq(0)
    expect(result[:display]).to eq(pnl: "$0.00", pct: "0.00%")
    expect(result[:tone]).to eq(:breakeven)
  end

  it "預估價介於兩平點與賣出腳：部分獲利，正號" do
    result = call("155")
    expect(result[:pnl]).to eq(BigDecimal("692.5"))
    expect(result[:display]).to eq(pnl: "+$692.50", pct: "+14.40%")
    expect(result[:tone]).to eq(:profit)
  end

  it "預估價高於賣出腳：封頂在最大獲利" do
    expect(call("500")[:pnl]).to eq(BigDecimal("1192.5"))
    expect(call("160")[:pnl]).to eq(BigDecimal("1192.5"))
  end

  it "預估價空白：回 nil（不顯示結果）" do
    expect(call("")).to be_nil
    expect(call(nil)).to be_nil
  end

  it "預估價 0（標的歸零）：屬於低於買入腳，虧掉全部淨成本" do
    result = call("0")
    expect(result[:pnl]).to eq(BigDecimal("-4807.5"))
    expect(result[:display]).to eq(pnl: "-$4,807.50", pct: "-100.00%")
  end

  it "預估價不是數字、非有限值或為負數：回錯誤" do
    expect(call("abc")).to eq(error: "預估股價格式錯誤：abc")
    expect(call("-5")).to eq(error: "預估股價格式錯誤：-5")
    # BigDecimal 解析得出 NaN／Infinity；NaN 若放行，clamp 會丟 ArgumentError 變成 500
    expect(call("NaN")).to eq(error: "預估股價格式錯誤：NaN")
    expect(call("Infinity")).to eq(error: "預估股價格式錯誤：Infinity")
  end

  it "兩腳參數不合法（K_S ≤ K_L、淨成本 ≤ 0 或 ≥ 寬度、格式錯誤）：回錯誤" do
    expect(call("150", short_strike: "100")).to have_key(:error)
    expect(call("150", d_mid: "0")).to have_key(:error)
    expect(call("150", d_mid: "60")).to have_key(:error)
    expect(call("150", long_strike: "x")).to have_key(:error)
  end
end
