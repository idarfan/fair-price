# frozen_string_literal: true

require "rails_helper"

# 2026-09-26 從 leaps_call_chain_fetcher_spec.rb 拆出（RuboCop RSpec/MultipleDescribes）。
RSpec.describe LeapsCallChainFetcher::SidecarRunner do
  it "超過時限就終止程序並丟出 Stalled（階段名稱與秒數寫在訊息裡）" do
    runner = described_class.new(command: ->(*) { [ "ruby", "-e", "sleep 10" ] })
    started = Time.current

    expect { runner.call(:chain, "ORCL", "2028-01-21-m", timeout: 1) }
      .to raise_error(LeapsCallChainFetcher::Stalled, /讀取 2028-01-21 chain 超過 1 秒沒有回應/)
    expect(Time.current - started).to be < 5
  end

  it "正常結束時回傳解析後的 JSON" do
    runner = described_class.new(command: ->(*) { [ "ruby", "-e", 'print %q({"status":"success","rows":[]})' ] })
    expect(runner.call(:chain, "ORCL", "2028-01-21-m", timeout: 5)).to eq("status" => "success", "rows" => [])
  end
end
