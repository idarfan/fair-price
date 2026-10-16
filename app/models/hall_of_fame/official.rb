# frozen_string_literal: true

module HallOfFame
  # 名人堂人物。名單只來自 config/hall_of_fame.yml（§1-6），由 OfficialSeeder 同步。
  class Official < ApplicationRecord
    CATEGORIES = %w[congress executive].freeze
    SOURCES    = %w[house oge].freeze

    has_many :filings, class_name: "HallOfFame::Filing", dependent: :restrict_with_exception

    validates :slug, :display_name, :last_name, :first_name, presence: true
    validates :slug, uniqueness: true
    validates :category, inclusion: { in: CATEGORIES }
    validates :source, inclusion: { in: SOURCES }
  end
end
