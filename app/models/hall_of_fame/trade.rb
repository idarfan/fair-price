# frozen_string_literal: true

module HallOfFame
  # 交易列（hof_transactions）。類別不叫 Transaction：Filing 上 has_many :transactions
  # 會蓋掉 ActiveRecord 的 #transaction 實例方法。
  class Trade < ApplicationRecord
    self.table_name = "hof_transactions"

    TX_TYPES = %w[P S S_partial E].freeze

    belongs_to :filing, class_name: "HallOfFame::Filing"
    has_one :option_detail, class_name: "HallOfFame::OptionDetail",
                            foreign_key: :transaction_id, inverse_of: :trade, dependent: :destroy

    validates :asset_name, presence: true
    validates :owner, inclusion: { in: Holding::OWNERS }
    # tx_type 解析不出時存 NULL、filing 標 needs_review（§1-5），不在這裡擋掉整列。
    validates :tx_type, inclusion: { in: TX_TYPES }, allow_nil: true
  end
end
