# frozen_string_literal: true

require "rails_helper"

RSpec.describe LeapsTableColumns do
  describe ".sanitize" do
    it "沒有存過順序時回預設順序" do
      expect(described_class.sanitize(nil)).to eq(described_class::DEFAULT_KEYS)
      expect(described_class.sanitize([])).to eq(described_class::DEFAULT_KEYS)
    end

    it "保留已存順序，原樣回傳合法的完整排列" do
      custom = described_class::DEFAULT_KEYS.rotate(3)

      expect(described_class.sanitize(custom)).to eq(custom)
    end

    it "丟掉已經不存在的欄位 key" do
      stored = described_class::DEFAULT_KEYS + %w[ghost_column]

      expect(described_class.sanitize(stored)).to eq(described_class::DEFAULT_KEYS)
    end

    it "去掉重複的 key" do
      stored = [ "iv" ] + described_class::DEFAULT_KEYS

      result = described_class.sanitize(stored)
      expect(result.count("iv")).to eq(1)
      expect(result.sort).to eq(described_class::DEFAULT_KEYS.sort)
    end

    # 這是 sanitize 存在的主要理由：日後程式新增欄位時，舊的順序快照裡沒有它，
    # 不能因此整欄消失，也不該退回預設順序把使用者排好的順序沖掉。
    it "程式新增欄位時，缺漏的 key 補回它原本的相對位置" do
      stored = described_class::DEFAULT_KEYS - %w[vega]

      result = described_class.sanitize(stored)
      expect(result.sort).to eq(described_class::DEFAULT_KEYS.sort)
      expect(result.index("vega")).to eq(result.index("iv") + 1)
    end
  end

  describe "常數一致性" do
    it "LABELS 與 DEFAULT_KEYS 一一對應" do
      expect(described_class::LABELS.keys.sort).to eq(described_class::DEFAULT_KEYS.sort)
    end

    it "SUBLABELS／DEFAULT_HIDDEN_KEYS／PDF_EXCLUDED_KEYS 都只引用已知欄位" do
      known = described_class::DEFAULT_KEYS
      expect(described_class::SUBLABELS.keys - known).to be_empty
      expect(described_class::DEFAULT_HIDDEN_KEYS - known).to be_empty
      expect(described_class::PDF_EXCLUDED_KEYS - known).to be_empty
    end
  end
end
