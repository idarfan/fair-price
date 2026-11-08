# frozen_string_literal: true

# 「推薦分析」標題下方的一句 LEAPS IV Rank 評語（leaps-iv-environment.md P6）。
# rank 先四捨五入到整數，顯示與判斷都用這個整數；門檻只讀 config/leaps_iv.yml 的 rank_thresholds。
# rank 為 nil（累積中、無資料、讀取失敗）時整句不出現。
module LeapsRecommendations::IvRankNote
  IV_RANK_NOTE_TEXT = {
    cheap:     "時間價值相對便宜。",
    neutral:   "IV 中性。",
    expensive: "時間價值偏貴；可考慮分批進場或改選更深價內（外在價值較低）的履約價。"
  }.freeze

  def render_iv_rank_note
    rank = @iv_environment.is_a?(Hash) ? @iv_environment[:rank] : nil
    return if rank.nil?

    shown = rank.round
    p(class: "text-xs text-gray-600 mt-1", data_leaps_iv_rank_note: "") do
      plain "LEAPS IV Rank #{shown}，#{IV_RANK_NOTE_TEXT.fetch(iv_rank_level(shown))}"
    end
  end

  private

  def iv_rank_level(shown)
    thresholds = LeapsIvConfig.fetch(:rank_thresholds)
    return :cheap if shown < thresholds.fetch("cheap")
    return :expensive if shown > thresholds.fetch("expensive")

    :neutral
  end
end
