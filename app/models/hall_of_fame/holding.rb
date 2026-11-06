# frozen_string_literal: true

module HallOfFame
  # 年報資產列。金額為申報區間上下限（§1-4）；value_max 為 NULL 代表無上限。
  class Holding < ApplicationRecord
    OWNERS = %w[self SP JT DC].freeze

    belongs_to :filing, class_name: "HallOfFame::Filing"

    validates :asset_name, presence: true
    validates :owner, inclusion: { in: OWNERS }
  end
end
