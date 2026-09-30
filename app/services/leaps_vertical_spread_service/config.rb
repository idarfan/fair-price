# frozen_string_literal: true

class LeapsVerticalSpreadService
  # config/leaps_vertical.yml 的參數（tasks/leaps-vertical-fix.md 通則 8）：r、每口每腳費用、IV 搜尋範圍。
  # 一律轉成 BigDecimal，與 service 內全程 BigDecimal 的計算一致。
  module Config
    PATH = Rails.root.join("config/leaps_vertical.yml")
    VALUES = YAML.load_file(PATH).freeze

    module_function

    def risk_free_rate = decimal("risk_free_rate")
    def fee_per_contract_leg = decimal("fee_per_contract_leg")
    def iv_bounds = BigDecimal(VALUES.fetch("iv_bounds").fetch("min").to_s)..BigDecimal(VALUES.fetch("iv_bounds").fetch("max").to_s)

    def decimal(key) = BigDecimal(VALUES.fetch(key).to_s)
  end
end
