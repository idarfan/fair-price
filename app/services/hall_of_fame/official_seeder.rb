# frozen_string_literal: true

module HallOfFame
  # 把 config/hall_of_fame.yml 的名單同步進 hof_officials（以 slug 為鍵，冪等）。
  # yml 格式錯誤直接拋 InvalidConfig，不略過任何一列。
  class OfficialSeeder
    class InvalidConfig < StandardError; end

    CONFIG_PATH      = Rails.root.join("config/hall_of_fame.yml")
    CATEGORY_SOURCES = { "congress" => "house", "executive" => "oge" }.freeze
    REQUIRED_KEYS    = %w[slug last first].freeze

    def initialize(config: nil)
      @config = config || YAML.safe_load_file(CONFIG_PATH)
    end

    # 回傳同步後的 Official 陣列。
    def call
      rows = build_rows
      ApplicationRecord.transaction do
        rows.map { |attrs| upsert(attrs) }
      end
    end

    private

    def build_rows
      raise InvalidConfig, "名單設定必須是 Hash（congress／executive）" unless @config.is_a?(Hash)

      unknown = @config.keys - CATEGORY_SOURCES.keys
      raise InvalidConfig, "未知的分類：#{unknown.join(', ')}" if unknown.any?

      @config.flat_map do |category, entries|
        Array(entries).map { |entry| row_for(category, entry) }
      end
    end

    def row_for(category, entry)
      missing = REQUIRED_KEYS.reject { |k| entry.is_a?(Hash) && entry[k].to_s.strip.present? }
      raise InvalidConfig, "#{category} 名單項目缺少 #{missing.join(', ')}：#{entry.inspect}" if missing.any?

      {
        slug:         entry["slug"].to_s,
        display_name: "#{entry['first']} #{entry['last']}",
        category:     category,
        source:       CATEGORY_SOURCES.fetch(category),
        last_name:    entry["last"].to_s,
        first_name:   entry["first"].to_s,
        district:     entry["district"]&.to_s,
        title:        entry["title"]&.to_s
      }
    end

    def upsert(attrs)
      official = Official.find_or_initialize_by(slug: attrs[:slug])
      official.assign_attributes(attrs)
      official.save!
      official
    end
  end
end
