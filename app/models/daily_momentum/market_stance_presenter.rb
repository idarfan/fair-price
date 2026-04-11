# frozen_string_literal: true

module DailyMomentum
  # Derives and exposes the market stance (aggressive/conservative/cash)
  # from VIX level. Single source of truth — shared by MarketStanceComponent
  # and ReportsController.
  class MarketStancePresenter
    STANCE_INFO = {
      aggressive:   { emoji: "🟢", label: "激進買入", color: "text-green-600",
                      desc: "市場情緒樂觀，低波動適合進場" },
      conservative: { emoji: "🟡", label: "保守買入", color: "text-yellow-600",
                      desc: "中性波動，謹慎選股分批進場" },
      cash:         { emoji: "🔴", label: "持幣觀望", color: "text-red-600",
                      desc: "高波動市場，建議保留現金等待機會" }
    }.freeze

    attr_reader :stance

    def initialize(vix: nil, es: nil, nq: nil, stance: nil)
      @vix    = vix
      @es     = es
      @nq     = nq
      @stance = stance || derive_stance(vix)
    end

    def info
      STANCE_INFO.fetch(@stance, STANCE_INFO[:cash])
    end

    def vix  = @vix
    def es   = @es
    def nq   = @nq

    # Also usable as a standalone method (for controllers etc.)
    def self.stance_from_vix(vix)
      new(vix: vix).stance
    end

    private

    def derive_stance(vix)
      return :cash if vix.nil?

      if    vix < MomentumThresholds::VIX_AGGRESSIVE_MAX    then :aggressive
      elsif vix <= MomentumThresholds::VIX_CONSERVATIVE_MAX then :conservative
      else                                                        :cash
      end
    end
  end
end
