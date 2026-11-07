# frozen_string_literal: true

# config/leaps_iv.yml 的唯一讀取點（leaps-iv-environment.md P4 排程與鎖、P6 rank_thresholds 共用）。
# 不分環境：排程、互動查詢、測試讀同一份。
module LeapsIvConfig
  PATH = Rails.root.join("config/leaps_iv.yml")

  def self.fetch(key) = load.fetch(key.to_s)

  def self.load
    YAML.safe_load_file(PATH)
  end
end
