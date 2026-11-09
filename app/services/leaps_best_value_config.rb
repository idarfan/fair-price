# frozen_string_literal: true

# config/leaps_best_value.yml 的唯一讀取點（leaps-best-value.md S1）。
# 不分環境：互動查詢、測試讀同一份。
module LeapsBestValueConfig
  PATH = Rails.root.join("config/leaps_best_value.yml")

  def self.load
    YAML.safe_load_file(PATH)
  end
end
