# frozen_string_literal: true

module HallOfFame
  # 期權列的補充資料（與 hof_transactions 1:1，P3b）。
  class OptionDetail < ApplicationRecord
    OPTION_RIGHTS   = %w[call put].freeze
    PREMIUM_SOURCES = %w[stated_contracts barchart_dom bs_model].freeze

    belongs_to :trade, class_name: "HallOfFame::Trade", foreign_key: :transaction_id,
                       inverse_of: :option_detail

    validates :transaction_id, uniqueness: true
    validates :option_right, inclusion: { in: OPTION_RIGHTS }, allow_nil: true
    validates :premium_source, inclusion: { in: PREMIUM_SOURCES }, allow_nil: true
  end
end
