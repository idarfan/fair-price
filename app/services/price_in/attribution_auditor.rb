# frozen_string_literal: true

# 匯出前掃描卡片文字，找出「提到了某家機構、但沒有列進來源白名單」的字詞。
#
# 背景是一個真實的誤標：手工製圖時把某投行的目標價依據標錯——年度、EPS 口徑、
# 有無折現三項全錯。歸屬一旦寫錯，整張圖的結論就站不住，而看圖的人沒有辦法
# 從圖上察覺。因此機構名只能來自使用者明確填入的白名單。
#
# 機構名只出現在這個檔案。locale 與元件內一律不得出現（S8 的驗證會 grep）——
# 把機構名寫進文案，等於在還沒填來源時就先替使用者掛上一個歸屬。
module PriceIn
  class AttributionAuditor
    INSTITUTION_KEYWORDS = [
      "美銀", "美银", "BofA", "Bank of America", "Arya",
      "高盛", "Goldman",
      "摩根", "Morgan", "大摩", "小摩",
      "巴克萊", "巴克莱", "Barclays",
      "UBS", "瑞銀", "瑞银",
      "花旗", "Citi",
      "Wells Fargo", "KeyBanc", "Stifel", "Cantor"
    ].freeze

    Hit = Data.define(:keyword, :allowed_by) do
      def allowed? = !allowed_by.nil?
    end

    def self.call(...) = new(...).call

    def initialize(text:, sources: [])
      @text    = text.to_s
      @sources = Array(sources).map(&:to_s).reject(&:blank?)
    end

    # 回傳「命中黑名單且不在白名單」的 Hit 清單。空陣列代表可以直接匯出。
    def call
      hits.reject(&:allowed?)
    end

    # 命中的全部（含已放行的）。警示視窗要顯示「因為什麼被放行」，
    # 只列被擋下的會讓使用者看不出白名單有沒有生效。
    def hits
      INSTITUTION_KEYWORDS
        .select { |kw| @text.include?(kw) }
        .map { |kw| Hit.new(keyword: kw, allowed_by: matching_source(kw)) }
    end

    private

    # 白名單項目只要包含該關鍵字即算放行——使用者填「美銀 2026/09 報告」
    # 應該要能放行「美銀」，要求逐字相等等於逼他填得跟黑名單一模一樣。
    def matching_source(keyword)
      @sources.find { |s| s.include?(keyword) }
    end
  end
end
