# frozen_string_literal: true

module HallOfFame
  # 由交易描述解析期權欄位（規格 P3b-2）；regex 放 config/hall_of_fame_option_patterns.yml。
  # 解析不全回 nil，由呼叫端標 needs_review，不猜值。
  class OptionDescriptionParser
    CONFIG_PATH = Rails.root.join("config/hall_of_fame_option_patterns.yml")
    OPTION_TEXT = /\b(call|put) options?\b/i

    Parsed = Data.define(:pattern, :option_right, :strike, :expiration, :contracts_stated, :exercise) do
      def exercise? = exercise
    end

    def self.config = @config ||= YAML.safe_load_file(CONFIG_PATH)

    # 規格 P3b-1：asset_type_code = OP，或描述含 call option／put option。
    def self.option_trade?(trade)
      trade.asset_type_code == "OP" || trade.description.to_s.match?(OPTION_TEXT)
    end

    def initialize(patterns: self.class.config.fetch("patterns"))
      @patterns = patterns.map do |p|
        [ p.fetch("name"), Regexp.new(p.fetch("regex"), Regexp::IGNORECASE), p.fetch("exercise", false) ]
      end
    end

    def parse(description)
      text = description.to_s.strip
      @patterns.each do |name, regex, exercise|
        match = regex.match(text)
        next unless match

        return build(name, match, exercise)
      end
      nil
    end

    private

    def build(name, match, exercise)
      expiration = parse_date(match[:expiration])
      return nil unless expiration

      Parsed.new(
        pattern:          name,
        option_right:     match[:right].downcase,
        strike:           BigDecimal(match[:strike].delete(",")),
        expiration:       expiration,
        contracts_stated: match.names.include?("contracts") ? match[:contracts].delete(",").to_i : nil,
        exercise:         exercise
      )
    end

    # M/D/YY 的兩位數年份補成 20xx。
    def parse_date(text)
      month, day, year = text.split("/").map(&:to_i)
      year += 2000 if year < 100
      Date.new(year, month, day)
    rescue Date::Error
      nil
    end
  end
end
