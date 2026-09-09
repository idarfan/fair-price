# frozen_string_literal: true

# 使用者輸入在進計算之前就被擋下，錯誤訊息說得出「為什麼」。
#
# 設計上最重要的一條：**`eps` 留空絕不可讓整個 Form invalid**。圖 A 與圖 B 是兩組
# 獨立的輸入，只填圖 A 的欄位就該看到圖 A，圖 B 顯示引導填寫的空狀態。若 eps 留空
# 讓 Form 整個失效，圖 A 也會跟著消失。
module PriceIn
  class ScenarioForm
    include ActiveModel::Model
    include ActiveModel::Attributes

    MAX_PRICE          = 100_000
    MAX_MULTIPLES      = 5
    MAX_SOURCES        = 5
    MAX_SOURCE_LENGTH  = 30
    MAX_HOLDING_YEARS  = 20
    TICKER_FORMAT      = /\A[A-Z]{1,5}(\.[A-Z])?\z/

    DEFAULT_TICKER            = "MRVL"
    DEFAULT_PRICE             = 223.55
    DEFAULT_CHART_A_MULTIPLES = [ 25, 30, 35 ].freeze
    DEFAULT_FISCAL_YEAR       = "FY2028"
    DEFAULT_CHART_B_YEAR      = "FY2029"
    DEFAULT_CHART_B_MULTIPLES = [ 20, 25, 33 ].freeze
    DEFAULT_ENTRY_B_PRICE     = 365

    attribute :ticker,                    :string
    attribute :price,                     :float
    attribute :price_as_of,               :datetime
    attribute :fiscal_year_label,         :string
    attribute :eps_band_low,              :float
    attribute :eps_band_high,             :float
    attribute :eps_band_label,            :string
    attribute :eps,                       :float
    attribute :chart_b_fiscal_year_label, :string
    attribute :entry_a_price,             :float
    attribute :entry_a_link_price,        :boolean, default: true
    attribute :entry_b_price,             :float
    attribute :holding_years,             :float
    attribute :discount_rate,             :float
    attribute :discount_years,            :float
    # 帶入現價時一併記下的 TTM EPS。只用來判定「使用者填的倍數是不是
    # 現價反推出來的那一個」，不參與任何估值計算。
    attribute :eps_ttm_hint,              :float

    attr_reader :chart_a_multiples, :chart_b_multiples, :attribution_sources

    # 使用者到底有沒有自己填倍數。輸入框預設留空（只給 placeholder 提示），
    # 但圖仍要畫得出來，所以留空時後端套預設值——兩件事必須分開記錄，
    # 否則「畫面顯示 25,30,35」與「使用者其實沒填」會被混為一談，
    # 按下「帶入」時就會變成預設值加上帶入值的一長串。
    def chart_a_multiples_provided? = @chart_a_multiples_provided
    def chart_b_multiples_provided? = @chart_b_multiples_provided

    # ── 建構 ────────────────────────────────────────────────

    # query string 進來的值可能是 "25,30,35"、["25","30"]、或 nil。
    # 三種都要吃，因為情境狀態一律走 URL，使用者會手改網址。
    def self.from_params(params)
      new(
        ticker:                    params[:ticker],
        price:                     params[:price],
        price_as_of:               params[:price_as_of],
        chart_a_multiples:         params[:chart_a_multiples],
        fiscal_year_label:         params[:fiscal_year_label],
        eps_band_low:              params[:eps_band_low],
        eps_band_high:             params[:eps_band_high],
        eps_band_label:            params[:eps_band_label],
        eps:                       params[:eps],
        chart_b_fiscal_year_label: params[:chart_b_fiscal_year_label],
        chart_b_multiples:         params[:chart_b_multiples],
        entry_a_price:             params[:entry_a_price],
        entry_a_link_price:        params[:entry_a_link_price],
        entry_b_price:             params[:entry_b_price],
        holding_years:             params[:holding_years],
        discount_rate:             params[:discount_rate],
        discount_years:            params[:discount_years],
        eps_ttm_hint:              params[:eps_ttm_hint],
        attribution_sources:       params[:attribution_sources]
      )
    end

    def initialize(attrs = {})
      attrs = attrs.symbolize_keys
      multiples_a = attrs.delete(:chart_a_multiples)
      multiples_b = attrs.delete(:chart_b_multiples)
      sources     = attrs.delete(:attribution_sources)

      # 只丟掉 nil（＝這個 key 根本沒給），不用 compact_blank。
      # `""` 與 `false` 在 Rails 都算 blank，但兩者都是使用者明確給的值：
      # ticker 填空字串必須被驗證擋下，entry_a_link_price 填 false 必須真的解除連結。
      # 若用 compact_blank，這兩種輸入會被靜靜換成預設值，驗證永遠不會觸發。
      given = attrs.compact
      super(given)

      self.ticker            = DEFAULT_TICKER      unless given.key?(:ticker)
      self.ticker            = normalize_ticker(ticker)
      self.price             = DEFAULT_PRICE       if price.nil?
      self.fiscal_year_label = DEFAULT_FISCAL_YEAR unless given.key?(:fiscal_year_label)

      @chart_a_multiples_provided = provided_list?(multiples_a)
      @chart_b_multiples_provided = provided_list?(multiples_b)
      @chart_a_multiples   = parse_decimal_list(multiples_a, DEFAULT_CHART_A_MULTIPLES)
      @chart_b_multiples   = parse_decimal_list(multiples_b, DEFAULT_CHART_B_MULTIPLES)
      @attribution_sources = parse_string_list(sources)

      apply_chart_b_defaults(given)
    end

    # ── 驗證 ────────────────────────────────────────────────

    validates :ticker, presence: true, format: {
      with: TICKER_FORMAT, message: "格式不正確（1–5 個英文字母，可含一個 .X 後綴，例如 MRVL、BRK.B）",
      allow_blank: true
    }
    validates :price, numericality: {
      greater_than: 0, less_than_or_equal_to: MAX_PRICE,
      message: "必須大於 0 且不超過 #{MAX_PRICE}"
    }, allow_nil: false
    validates :fiscal_year_label, presence: {
      message: "必填。price / multiple 這個算式裡沒有時間，「FY2028 賺到 7.45」和「FY2031 賺到 7.45」" \
               "是完全不同的兩件事，缺年度的圖會誤導"
    }

    validate :validate_chart_a_multiples
    validate :validate_eps_band
    validate :validate_eps
    validate :validate_chart_b
    validate :validate_holding_years
    validate :validate_discount
    validate :validate_attribution_sources

    # ── 圖 B 是否出圖 ────────────────────────────────────────

    # eps 留空 = 空狀態，不是錯誤。
    def chart_b_ready? = eps.present? && eps.to_f.positive?

    # ── 自動組出的標籤 ──────────────────────────────────────
    #
    # 這兩個不是輸入欄位。寫死的標籤在報價帶入後會與長條對不上，圖例直接說謊。

    def entry_a_label = "買入基準 #{Formatter.money(entry_a_price)}"
    def entry_b_label = "假設買入價 #{Formatter.money(entry_b_price)}"

    # ── 連結價格 ────────────────────────────────────────────

    def price=(value)
      super
      super_entry_sync
    end

    def entry_a_link_price=(value)
      super
      super_entry_sync
    end

    # ── 不阻擋出圖的提示 ────────────────────────────────────
    #
    # 年化值錯得很隱蔽，看不出來，所以提示但不擋。
    def warnings
      list = []
      list << circular_multiple_warning   if circular_multiples.any?
      list << holding_years_mismatch_warning if holding_years_mismatch?
      list.compact
    end

    def price_source_label = price_as_of.present? ? "報價時間 #{price_as_of.strftime('%Y-%m-%d %H:%M')}" : "手動輸入"

    private

    def super_entry_sync
      self.entry_a_price = price if entry_a_link_price
    end

    def apply_chart_b_defaults(given)
      self.chart_b_fiscal_year_label = DEFAULT_CHART_B_YEAR unless given.key?(:chart_b_fiscal_year_label)
      self.entry_b_price             = DEFAULT_ENTRY_B_PRICE if entry_b_price.nil?
      self.entry_a_price             = price if entry_a_link_price || entry_a_price.nil?
    end

    def normalize_ticker(value) = value.to_s.strip.upcase

    def provided_list?(raw)
      return false if raw.nil?

      items = raw.is_a?(Array) ? raw : raw.to_s.split(",")
      items.any? { |v| v.to_s.strip.present? }
    end

    # "25,30,35" / ["25","30"] / nil 三種都吃。
    # 空字串（欄位留空送出）視同沒填，套預設值——否則圖 A 會因為
    # 「至少要填 1 個」而整張消失，但使用者只是沒動那一格。
    def parse_decimal_list(raw, fallback)
      return fallback.map(&:to_f) unless provided_list?(raw)

      items = raw.is_a?(Array) ? raw : raw.to_s.split(",")
      items.map { |v| v.to_s.strip }.reject(&:empty?).map(&:to_f)
    end

    def parse_string_list(raw)
      return [] if raw.nil?

      items = raw.is_a?(Array) ? raw : raw.to_s.split(",")
      items.map { |v| v.to_s.strip }.reject(&:empty?)
    end

    def validate_chart_a_multiples
      validate_multiple_list(chart_a_multiples, :chart_a_multiples, "圖 A 的本益比")
    end

    def validate_multiple_list(list, field, label)
      if list.empty?
        errors.add(field, "#{label}至少要填 1 個")
      elsif list.size > MAX_MULTIPLES
        errors.add(field, "#{label}最多 #{MAX_MULTIPLES} 個，目前有 #{list.size} 個")
      end
      errors.add(field, "#{label}必須都大於 0")     if list.any? { |m| m <= 0 }
      errors.add(field, "#{label}不可重複")         if list.size != list.uniq.size
    end

    def validate_eps_band
      low_present  = eps_band_low.present?
      high_present = eps_band_high.present?

      if low_present ^ high_present
        errors.add(:eps_band_high, "EPS 預測區間的上下限要同時填寫，或同時留空")
        return
      end
      return unless low_present

      errors.add(:eps_band_high, "區間上限必須大於或等於下限") if eps_band_high < eps_band_low
      errors.add(:eps_band_label, "有填 EPS 預測區間時，必須說明這個區間的來源") if eps_band_label.blank?
    end

    def validate_eps
      return if eps.nil?

      errors.add(:eps, "填了就必須大於 0（留空則圖 B 顯示空狀態，不算錯誤）") if eps <= 0
    end

    # 只有在 eps 有值時才驗證圖 B 的欄位。這是「條件必填」的關鍵：
    # 使用者只想看圖 A 時，圖 B 的欄位不該把整張表單擋下來。
    def validate_chart_b
      return unless chart_b_ready?

      errors.add(:chart_b_fiscal_year_label, "填了 EPS 就必須說明這是哪一年的 EPS") if chart_b_fiscal_year_label.blank?
      validate_multiple_list(chart_b_multiples, :chart_b_multiples, "圖 B 的本益比")

      errors.add(:entry_a_price, "買入基準價必須大於 0") if entry_a_price.nil? || entry_a_price <= 0
      if entry_b_price.nil? || entry_b_price <= 0
        errors.add(:entry_b_price, "假設買入價必須大於 0")
      elsif entry_a_price.present? && entry_b_price == entry_a_price
        errors.add(:entry_b_price, "假設買入價與買入基準價相同，兩條長條會完全重疊，看不出買入價的代價")
      end
    end

    def validate_holding_years
      return if holding_years.nil?

      return if holding_years.positive? && holding_years <= MAX_HOLDING_YEARS

      errors.add(:holding_years, "必須大於 0 且不超過 #{MAX_HOLDING_YEARS} 年")
    end

    def validate_discount
      rate_present  = discount_rate.present?
      years_present = discount_years.present?

      if rate_present ^ years_present
        errors.add(:discount_years, "折現率與折現年數要同時填寫，或同時留空")
        return
      end
      return unless rate_present

      errors.add(:discount_rate, "折現率請填 0 到 1 之間的小數（例如 0.13 代表 13%）") unless discount_rate.between?(0, 1)
    end

    def validate_attribution_sources
      if attribution_sources.size > MAX_SOURCES
        errors.add(:attribution_sources, "最多 #{MAX_SOURCES} 項，目前有 #{attribution_sources.size} 項")
      end
      return if attribution_sources.all? { |s| s.length <= MAX_SOURCE_LENGTH }

      errors.add(:attribution_sources, "每一項不得超過 #{MAX_SOURCE_LENGTH} 字")
    end

    # ── 循環論證 ────────────────────────────────────────
    #
    # 使用者按「本益比 (P/E)」的帶入之後，倍數就是「現價 ÷ TTM EPS」。
    # 拿它回去算所需 EPS，必然得到 TTM EPS——圖上圓點的位置完全由這個
    # 恆等式決定，跟公司值不值這個價無關。
    #
    # 這個警告放在頁面最上方而不是只寫在說明卡裡：說明卡預設收起，
    # 真正踩到坑的人看不到它。
    def circular_multiples
      return [] if eps_ttm_hint.nil? || eps_ttm_hint.to_f <= 0 || price.to_f <= 0

      implied = price.to_f / eps_ttm_hint.to_f
      chart_a_multiples.select { |m| (m - implied).abs <= implied * 0.02 }
    end

    def circular_multiple_warning
      list = circular_multiples.map { |m| Kernel.format("%g", m) }.join("、")
      "倍數 #{list} 就是「現價 ÷ 目前 EPS」算出來的。用它回推所需 EPS 必然得到目前的 EPS，" \
        "這個比較是循環論證，不能用來判斷貴或便宜——倍數要換成你自己的判斷（歷史中位數、同業中位數，" \
        "或你說得出理由的數字）。"
    end

    # 2026-09-09：原本這裡有「標題年度 ≠ 色帶來源年度」的警告，已移除。
    # 圖 A 的兩個年度本來就該不同：左側長條是「現價現在要求賺多少」（本財政
    # 年度），右側綠帶是「分析師認為未來賺得到多少」（下一財政年度），
    # 不同年度才有比較的意義。警告會在正確的設定下每次都叫。
    #
    # 兩個年度各自標在畫面上：標題寫 ② 的年度，圖例寫綠帶自己的年度
    # （見 ChartACardComponent#band_legend_label），使用者看得到差異。

    # 年度標籤裡的西元年與持有年數對不對得起來
    def holding_years_mismatch?
      return false if holding_years.nil? || chart_b_fiscal_year_label.blank?

      year = chart_b_fiscal_year_label[/\d{4}/]&.to_i
      return false if year.nil?

      (year - Date.current.year - holding_years).abs > 1
    end

    def holding_years_mismatch_warning
      year = chart_b_fiscal_year_label[/\d{4}/].to_i
      "#{chart_b_fiscal_year_label} 距今約 #{year - Date.current.year} 年，但持有年數填的是 " \
        "#{holding_years} 年。年化報酬會照 #{holding_years} 年計算——請確認這是你要的。"
    end
  end
end
