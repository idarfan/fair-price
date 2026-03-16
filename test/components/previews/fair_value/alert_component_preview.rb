# frozen_string_literal: true

# @label Alert
class FairValue::AlertComponentPreview < Lookbook::Preview
  layout "component_preview"

  # @label Error (default)
  # @param message text "Alert message text"
  # @param title text "Optional bold title"
  # @param dismissible toggle
  def error(message: "找不到股票：INVALID（請確認代號正確）", title: "查詢失敗", dismissible: false)
    render FairValue::AlertComponent.new(message:, type: :error, title:, dismissible:)
  end

  # @label Warning
  # @param message text
  def warning(message: "API 金鑰即將到期，請至 Finnhub 更新設定")
    render FairValue::AlertComponent.new(message:, type: :warning, title: "注意")
  end

  # @label Info
  # @param message text
  def info(message: "數據來源 Finnhub，每分鐘最多 60 次查詢")
    render FairValue::AlertComponent.new(message:, type: :info)
  end

  # @label Success
  # @param message text
  def success(message: "分析完成：AAPL Apple Inc.")
    render FairValue::AlertComponent.new(message:, type: :success)
  end

  # @label All types
  def all_types
    render_with_template
  end
end
