require "rails_helper"

RSpec.describe TrackedTicker, type: :model do
  # ── Validations ─────────────────────────────────────────────────────────────

  describe "validations" do
    it "is valid with required attributes" do
      expect(build(:tracked_ticker)).to be_valid
    end

    it "is invalid without symbol" do
      expect(build(:tracked_ticker, symbol: nil)).not_to be_valid
    end

    it "is invalid when symbol is duplicated (case-insensitive)" do
      create(:tracked_ticker, symbol: "AAPL")
      expect(build(:tracked_ticker, symbol: "aapl")).not_to be_valid
    end
  end

  # ── Callbacks ────────────────────────────────────────────────────────────────

  describe "before_save: upcase symbol" do
    it "upcases and strips symbol on save" do
      ticker = create(:tracked_ticker, symbol: " tsla ")
      expect(ticker.symbol).to eq("TSLA")
    end
  end

  # ── Associations ─────────────────────────────────────────────────────────────

  describe "associations" do
    it "has many option_snapshots" do
      ticker   = create(:tracked_ticker)
      snapshot = create(:option_snapshot, tracked_ticker: ticker)
      expect(ticker.option_snapshots).to include(snapshot)
    end

    it "destroys option_snapshots on delete" do
      ticker = create(:tracked_ticker)
      create(:option_snapshot, tracked_ticker: ticker)
      expect { ticker.destroy }.to change(OptionSnapshot, :count).by(-1)
    end
  end

  # ── Scopes ───────────────────────────────────────────────────────────────────

  describe ".active" do
    it "returns only active tickers" do
      active   = create(:tracked_ticker, active: true)
      inactive = create(:tracked_ticker, active: false)
      expect(described_class.active).to include(active)
      expect(described_class.active).not_to include(inactive)
    end
  end

  # ── Config accessors ─────────────────────────────────────────────────────────

  describe "config accessors" do
    context "with explicit config values" do
      let(:ticker) { build(:tracked_ticker, config: { "min_dte" => 14, "max_dte" => 60, "strike_range" => 0.2 }) }

      it "returns min_dte from config" do
        expect(ticker.min_dte).to eq(14)
      end

      it "returns max_dte from config" do
        expect(ticker.max_dte).to eq(60)
      end

      it "returns strike_range from config" do
        expect(ticker.strike_range).to eq(0.2)
      end
    end

    context "with empty config (defaults)" do
      let(:ticker) { build(:tracked_ticker, config: {}) }

      it "defaults min_dte to 7" do
        expect(ticker.min_dte).to eq(7)
      end

      it "defaults max_dte to 90" do
        expect(ticker.max_dte).to eq(90)
      end

      it "defaults strike_range to 0.3" do
        expect(ticker.strike_range).to eq(0.3)
      end
    end
  end

  # ── Instance methods ─────────────────────────────────────────────────────────

  describe "#last_snapshot_date" do
    it "returns nil when there are no snapshots" do
      ticker = create(:tracked_ticker)
      expect(ticker.last_snapshot_date).to be_nil
    end

    it "returns the most recent snapshot_date" do
      ticker = create(:tracked_ticker)
      create(:option_snapshot, tracked_ticker: ticker, snapshot_date: Date.today - 3)
      create(:option_snapshot, tracked_ticker: ticker, snapshot_date: Date.today,
             contract_symbol: "AAPL230120C00150000", option_type: "call")
      expect(ticker.last_snapshot_date).to eq(Date.today)
    end
  end

  # 2026-08-30 稽核（database_consistency）：本 model 原本寫
  # `uniqueness: { case_sensitive: false }`。那個寫法有兩個問題：
  #
  #   1. 代號存檔前一律 upcase，DB 裡只有大寫，比對大小寫毫無意義；
  #      而 case_sensitive: false 會產生 LOWER(...) = LOWER($1)，
  #      用不到既有的 btree 唯一索引。
  #   2. 正規化原本寫在 before_save——也就是驗證「之後」。單獨拿掉
  #      case_sensitive: false 會讓 "aapl" 通過唯一性驗證、存檔時才
  #      upcase 成 "AAPL" 撞上唯一索引，使用者看到 500 而不是驗證錯誤。
  #
  # 所以正規化被搬到 before_validation。下面釘住的就是那個順序：
  # 少了這些測試，把 before_validation 改回 before_save 不會有任何測試失敗。
  it "小寫輸入會被正規化成大寫" do
    expect(described_class.create!(symbol: "aapl").symbol).to eq("AAPL")
  end

  it "小寫重複輸入是驗證錯誤，不是資料庫例外" do
    described_class.create!(symbol: "AAPL")

    dup = described_class.new(symbol: "aapl")

    # 正規化若跑在驗證之後，這裡會是 valid? == true 然後 save 時炸 RecordNotUnique
    expect(dup).not_to be_valid
    expect(dup.errors[:symbol]).to be_present
  end

  it "前後空白會被去掉" do
    expect(described_class.create!(symbol: "  msft  ").symbol).to eq("MSFT")
  end
end
